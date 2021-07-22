variable "domain_name" {
    description = "The TLD that will be used within this sytem."
    type        = string 
}

variable "bucket_name" {
    description = "The name of the bucket to store emails in"
    type        = string
}

variable "account_id" {
    description = "The AWS Account ID"
    type        = string
}

variable "forward_mapping" {
    description = "A map of where to send emails"
    type        = string
}

variable "recipients" {
    description = "A list of the receiving emails"
    type        = list(string)
}