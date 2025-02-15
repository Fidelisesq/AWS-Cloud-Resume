output "api_gateway_url" {
  value       = "${aws_api_gateway_stage.cloud_resume_stage.invoke_url}/visitors"
  description = "Invoke URL for the API Gateway"
}