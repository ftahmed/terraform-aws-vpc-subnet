project               = "eo"
environment           = "production"
region                = "eu-west-2"
profile               = "m4travel"
availability_zones    = ["eu-west-2a", "eu-west-2b"]
// https://medium.com/aws-activate-startup-blog/practical-vpc-design-8412e1a18dcc
/*
10.0.0.0/16:
    10.0.0.0/18 — AZ A
        10.0.0.0/19 — Private
        10.0.32.0/19
               10.0.32.0/20 — Public
               10.0.48.0/20
                   10.0.48.0/21 — Protected
                   10.0.56.0/21 — Spare
    10.0.64.0/18 — AZ B
        10.0.64.0/19 — Private
        10.0.96.0/19
                10.0.96.0/20 — Public
                10.0.112.0/20
                    10.0.112.0/21 — Protected
                    10.0.120.0/21 — Spare
    10.0.128.0/18 — AZ C
        10.0.128.0/19 — Private
        10.0.160.0/19
                10.0.160.0/20 — Public
                10.0.176.0/20
                    10.0.176.0/21 — Protected
                    10.0.184.0/21 — Spare
    10.0.192.0/18 — Spare
*/
vpc_cidr              = "10.0.0.0/16"
private_subnets_cidr  = ["10.0.0.0/19", "10.0.64.0/19"] // List of private subnet cidr range
public_subnets_cidr   = ["10.0.32.0/20", "10.0.96.0/20"] // List of public subnet cidr range
