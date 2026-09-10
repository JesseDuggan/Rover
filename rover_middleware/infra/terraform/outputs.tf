output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.rover.id
}

output "cognito_flutter_client_id" {
  value = aws_cognito_user_pool_client.flutter.id
}
