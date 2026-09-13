# Temporary Research Capture

Normal route-story status reports rejection counts without response text or location context.
To investigate a response that contains no usable cited passages:

1. Deploy the commit containing `CaptureRejectedResponses`.
2. Set Railway variable `ROVER_LOCAL_RESEARCH_CAPTURE_REJECTIONS=true` on the Rover service.
3. After deployment is active, generate one fresh route and wait for research to finish.
4. Search its deployment logs for `RoverResearchCapture` (event ID 6101, warning level).
5. Set the variable to `false` after collecting the entry.

Capture is disabled by default. It records only rejected search responses, without retries.
The entry contains model name, the already-coarsened research context (up to 4,000 characters),
search-call count, rejection counts, response length, and a response excerpt (up to 2,000 characters).
It does not log HTTP headers, API keys, walk IDs, or the precise route trace. The configured API
key is redacted if it appears in text. Raw text is never added to the app status.

The context still contains approximate coordinates, public place names, interests, and locality
labels. Response text is untrusted provider output and may contain additional place information.
Treat the entry as sensitive, redact it before sharing publicly, and follow the deployment's
log retention policy. Disabling capture does not delete existing log entries.

Capture cannot recover responses from earlier runs. An absent entry can mean the flag is off,
the wrong deployment is being inspected, or research failed in another stage. Do not infer that
search succeeded from the absence of a capture entry.
