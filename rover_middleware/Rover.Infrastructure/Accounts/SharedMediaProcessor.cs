using System.Diagnostics;
using System.Globalization;
using System.Text.Json;

namespace Rover.Infrastructure.Accounts;

public sealed class SharedMediaProcessor(string ffmpeg = "ffmpeg", string ffprobe = "ffprobe")
{
    public async Task Process(string input,string output,string kind,CancellationToken cancellationToken)
    {
        var format=kind=="video"?"mov":"mjpeg";
        var probe=await Run(ffprobe,["-v","error","-protocol_whitelist","file","-f",format,"-show_entries","format=duration:stream=codec_type,width,height","-of","json",input],cancellationToken);
        using var json=JsonDocument.Parse(probe);
        var videos=json.RootElement.GetProperty("streams").EnumerateArray().Where(s=>s.GetProperty("codec_type").GetString()=="video").ToArray();
        if(videos.Length!=1 || !videos[0].TryGetProperty("width",out var w) || !videos[0].TryGetProperty("height",out var h) ||
           w.GetInt32()<=0 || h.GetInt32()<=0 || (long)w.GetInt32()*h.GetInt32()>20_000_000)
            throw new FriendsException(400,"Unsupported image or video dimensions.");
        if(kind=="video") {
            if(!json.RootElement.GetProperty("format").TryGetProperty("duration",out var duration) ||
               !double.TryParse(duration.GetString(),NumberStyles.Float,CultureInfo.InvariantCulture,out var seconds) || !double.IsFinite(seconds) || seconds<=0 || seconds>60.5)
                throw new FriendsException(400,"Videos must be no longer than 60 seconds.");
        }
        // Decode and re-encode instead of copying EXIF, QuickTime tags or auxiliary tracks.
        var args=new List<string>{"-v","error","-nostdin","-y","-threads","1","-protocol_whitelist","file","-f",format,"-i",input,"-map","0:v:0","-map_metadata","-1","-map_chapters","-1"};
        if(kind=="video") args.AddRange(["-map","0:a:0?","-vf","scale=1280:1280:force_original_aspect_ratio=decrease:force_divisible_by=2","-c:v","libx264","-preset","veryfast","-crf","25","-pix_fmt","yuv420p","-threads","1","-c:a","aac","-b:a","96k","-t","60","-movflags","+faststart","-f","mp4"]);
        else args.AddRange(["-frames:v","1","-vf","scale=1920:1920:force_original_aspect_ratio=decrease","-c:v","mjpeg","-q:v","3","-threads","1","-f","image2"]);
        args.AddRange(["-map_metadata:s","-1"]);
        args.Add(output); await Run(ffmpeg,args,cancellationToken);
        if(new FileInfo(output).Length is <=0 or >67_108_864) throw new FriendsException(400,"Memory is too large to share.");
    }
    private static async Task<string> Run(string executable,IEnumerable<string> args,CancellationToken cancellationToken)
    {
        using var timeout=CancellationTokenSource.CreateLinkedTokenSource(cancellationToken); timeout.CancelAfter(TimeSpan.FromMinutes(2));
        var start=new ProcessStartInfo(executable){UseShellExecute=false,RedirectStandardError=true,RedirectStandardOutput=true,CreateNoWindow=true};
        foreach(var arg in args) start.ArgumentList.Add(arg);
        using var process=new Process{StartInfo=start};
        try { process.Start(); }
        catch(System.ComponentModel.Win32Exception) { throw new FriendsException(503,"Media processing is unavailable. Try again later."); }
        var output=process.StandardOutput.ReadToEndAsync(timeout.Token); var errors=process.StandardError.ReadToEndAsync(timeout.Token);
        try { await process.WaitForExitAsync(timeout.Token); await errors; }
        catch { try { process.Kill(entireProcessTree:true); } catch(InvalidOperationException) { } throw; }
        if(process.ExitCode!=0) throw new FriendsException(400,"This file could not be processed. Share a JPEG photo or an MP4 video.");
        return await output;
    }
}
