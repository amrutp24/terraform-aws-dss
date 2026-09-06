# terraform-aws-dss

Runs [Dataiku DSS](https://www.dataiku.com/) on an EC2 instance.

The module creates a security group and an instance, then installs DSS through
user-data: download, install, apply a licence, register the boot service, and
optionally mint the API key needed to configure the instance afterwards.

| Requirement | Version |
| --- | --- |
| Terraform | >= 1.5 |
| `hashicorp/aws` | ~> 6.0 |

## Usage

```hcl
provider "aws" {
  region = "eu-west-1"
}

module "dss" {
  source  = "amrutp24/dss/aws"
  version = "~> 0.1"

  allowed_cidr_blocks = ["203.0.113.0/24"] # replace: your office or VPN range
  license_json        = var.dss_license_json
}

output "dss_url" {
  value = module.dss.dss_url
}
```

`203.0.113.0/24` above is RFC 5737 documentation space and matches nothing real.
Put your own range there.

With no `vpc_id` the instance lands in the account's default VPC and takes the
first subnet it finds, which is fine for a trial and not for production. Set
`vpc_id` and `subnet_id` to place it deliberately.

## While it installs

`terraform apply` returns in about a minute. DSS does not answer for several
more: the installer pulls down roughly two gigabytes and then builds a Python
environment. Until that finishes the port refuses connections outright, so a
browser shows a connection error rather than a DSS page.

To watch it, read the user-data log on the instance:

```bash
ssh ubuntu@$(terraform output -raw public_ip) 'sudo tail -f /var/log/cloud-init-output.log'
```

Every line the bootstrap writes is prefixed `[dss-bootstrap]`, and the last one
is `done`. Without SSH the same output is in the console log, under
Actions → Monitor and troubleshoot → Get system log.

To block until it is up:

```bash
until curl -sf "$(terraform output -raw dss_url)" >/dev/null; do sleep 15; done
```

If it never comes up, that log names the step that failed. DSS keeps its own
logs under `run/` inside the data directory once the installer has got that far.

## Configuring DSS is a second apply

This module gets you a running instance. Everything inside it (projects, groups,
connections, code environments) belongs to the
[`dataiku` provider](https://registry.terraform.io/providers/amrutp24/dataiku/latest),
and that has to live in a **separate root configuration**.

Terraform builds provider configuration during planning, before any resource
exists. One configuration that created this instance and also pointed the
`dataiku` provider at it would need the address, and an API key from a machine
that has not booted yet, just to produce a plan. It deadlocks, and no
arrangement of modules gets around it.

So apply this, wait for DSS to answer, then apply a second configuration that
reads these outputs:

```hcl
provider "dataiku" {
  host = data.terraform_remote_state.instance.outputs.dss_url
  # api_key from DATAIKU_API_KEY
}
```

The split earns its keep anyway. You can rebuild the instance without touching
its configuration, and change configuration without risking the instance.

## Getting the API key out

The `dataiku` provider needs an API key, and a brand-new DSS has no way to
produce one without a browser. With `create_api_key` left on, the bootstrap runs
`dsscli api-key-create` and writes the result to `api_key_path`, mode 0600.

Moving it off the instance is the part this module deliberately leaves to you.
Secrets Manager is the cleanest option: extend the instance's role, push the key
there from user-data, and read it back with `aws_secretsmanager_secret_version`,
so nothing sensitive passes through Terraform state. Fetching the file over SSH
with an `external` data source works too.

Or skip it. Set `create_api_key = false` and create a global API key under
Administration → Security once DSS is up.

## Outputs

| Output | Use |
| --- | --- |
| `dss_url` | The `dataiku` provider's `host`. |
| `public_ip`, `private_ip` | Instance addresses. |
| `instance_id` | SSM sessions, snapshots, anything referencing the instance. |
| `data_dir` | Path holding every project. This is what to back up. |

## Limits

The data directory sits on the root volume, which keeps the module small and
means replacing the instance loses every project. Attach an EBS volume and mount
it at `data_dir` if you want it to survive a rebuild.

There is no load balancer, TLS or DNS. DSS answers directly on its port over
plain HTTP, so put it behind an ALB with an ACM certificate before anyone types
a password into it.

Nothing replaces a broken node either: no autoscaling group, no health check.
DSS is stateful and does not cluster this way, so recovery means restoring the
data directory from a backup you took yourself.

It also costs money. DSS drops into a low-memory mode below roughly 16 GB and
says so in its logs, so the default is `m5.xlarge`, which bills for as long as
it exists. Destroy it when you are done.

## Licensing DSS

The `dataiku` provider talks to the DSS public REST API, and the Free Edition
does not licence that on its own. The Enterprise trial bundled with it does, for
as long as the trial lasts. Pass a licence at install time with `license_json`,
or register the instance through its web interface on first visit.

`license_json` reaches instance user-data and Terraform state, so supply it from
a secret store rather than a file in your repository.

## Security defaults

`allowed_cidr_blocks` has **no default and refuses `0.0.0.0/0`**. DSS holds your
data, and its login page should not become reachable from the whole internet
because a variable had a convenient default. Edit the validation if you
genuinely mean it.

SSH is closed unless you set `ssh_cidr_blocks`. IMDSv2 is required, and the root
volume is encrypted.

## License

Mozilla Public License 2.0.
