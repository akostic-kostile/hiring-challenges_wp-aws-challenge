# Hiring challenges - Wordpress AWS challenge

## What it does

This Terraform configuration deploys highly available Wordpress stack to AWS. It creates VCP, subnets (default is 2, but can create any number of subnets up to maximum number of availability zones. So, 3 for eu-central-1 but 6 for us-east-1), instances (default is 2), ELB, routing tables and multi-AZ RDS database.   

## How to use it

Edit the terraform.tfvars file, there are 4 settings that you have to input, everything else has sane defaults:
- aws_access_key, access key of IAM account with sufficient privileges
- aws_secret_key, secret access key of IAM account with sufficient privileges
- key_name, key name as it was uploaded to EC2 -> Key Pairs
- private_key_path, local path to the corresponding private key

There are other variables that can be overwritten, take a look at the terraform.tfvars file.

**Note: Leaving passwords in cleartext inside a git repo is a bad idea, it is only here as a proof of concept, make sure you secure any sensitive information!**

After that all that is needed is to do this:
```sh
$ terraform init
$ terraform plan -out wp-aws-challenge.tfplan
$ terraform apply "wp-aws-challenge.tfplan"
```

## Output

After the script is done it will output DNS endpoint of ELB that can be used to access Wordpress and finish the installation process.

## Improvements

- Obviously SSL would be a big improvement here. I decided not to use it as that would either require a real certificate (which costs money and would add the need to do some DNS management) or a selfsigned one which would output a warning in all broswers, and that sort of defeats the purpose.
- RDS instance is also using the same (public) subnets as EC2 instances. Adding private subnets just for 1 RDS instance seemed unnecessary for a proof of concept such as this as it would complicate the whole configuration by a fair amount without adding much practical benefit. So RDS instance is only protected by a security group.
- Script is faily slow, EC2 instances are waiting for RDS to be fully provisioned because they need to write DB endpoint into a configuration file. RDS provisioning takes 10-15 minutes, can't really think of a good way to speed this process.
