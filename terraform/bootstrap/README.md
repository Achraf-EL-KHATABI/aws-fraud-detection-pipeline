# Bootstrap — Remote Terraform Backend

This sub-project creates the two AWS resources required to host the **remote
Terraform state** of the main project:

- An **S3 bucket** (versioned, encrypted, private) → stores `terraform.tfstate`
- A **DynamoDB table** (`LockID` as hash key) → state locking

It is applied **once**, manually, with **local state**. Subsequent changes to
the main project use the remote backend created here.

## Apply

```bash
cd terraform/bootstrap
terraform init
terraform plan
terraform apply
```

At the end, the output `backend_config_snippet` prints the exact `backend "s3"`
block to copy into `../backend.tf`.

## Why is the local state file gitignored?

The local `terraform.tfstate` produced by this bootstrap is **not** committed
on purpose. The two resources it tracks are trivial to recreate or
`terraform import` if needed, and the file can contain account-specific
metadata.

## Destroying

The S3 bucket is protected by `lifecycle { prevent_destroy = true }`.
To remove the backend (rarely needed), first delete that block, run
`terraform apply`, then `terraform destroy`.
