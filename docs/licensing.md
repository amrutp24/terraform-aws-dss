# Getting a licence onto the instance

DSS will install and run without a licence, but a fresh instance asks whoever
opens it first to register Free Edition: a form wanting a first name, a last
name and an email address. Until somebody fills that in, the instance
licenses only the `NONE` user profile, which means the dataiku provider cannot
create a usable user and `terraform apply` on a configuration that creates
one will fail.

That makes a rebuild a manual job, which is the thing worth fixing if you
destroy and recreate often.

One clarification first, because it is easy to expect too much: none of this
removes the DSS **login page**. DSS is an application with user accounts and
always asks for credentials, `admin` / `admin` on a fresh install. What the
options below remove is the **registration form**.

## Option A: store the licence, let the instance read it

This is what `license_ssm_parameter` is for. Register once, keep the licence
in SSM Parameter Store, and every instance after that reads it at boot and
installs it before DSS finishes starting.

1. Bring up an instance and register Free Edition in the browser, once.
2. Copy the licence into Parameter Store while that instance is still up:

   ```
   ./scripts/save-license.sh
   ```

   It reads the licence off the host, checks it looks like a licence, and
   stores it as a `SecureString`. It prints nothing: the licence goes from the
   instance to Parameter Store without passing through your terminal.

3. Name the parameter in your module call:

   ```hcl
   module "dss" {
     source  = "amrutp24/dss/aws"
     version = "~> 0.2"

     license_ssm_parameter = "/dss/license"
     # ...
   }
   ```

From then on `terraform apply` produces a licensed instance with no browser
step. The boot log says so:

```
[dss-bootstrap] fetching licence
[dss-bootstrap] licence fetched
[+] Installing license file
```

Two things worth knowing about how this works:

- **The licence is portable.** Its `instanceId` is generated during
  registration and travels inside the signed licence rather than being
  derived from the hardware, so the same licence works on a machine that did
  not exist when it was issued. That is what makes storing it viable at all.
- **The instance reads the parameter itself**, which is why naming one creates
  an instance profile even with `enable_ssm` off. Only the parameter name
  reaches Terraform state and instance user-data; the licence does not.

`license_json` does the same job in one step and is simpler, but it is
rendered into the boot script, so the licence ends up in Terraform state and
in instance metadata where anyone with `ec2:DescribeInstanceAttribute` can
read it back. Prefer the parameter.

## Option B: let the instance register itself

Not implemented here, and described so you can decide against it knowingly.

Selecting Free Edition in the browser sends one unauthenticated request:

```
POST /api/registration/initial-register-community
  userFirstName, userLastName, userEmail, instanceId
```

Dataiku answers with a signed licence and DSS writes it to
`<data_dir>/config/license.json`. A step in the bootstrap could do the same
with `curl` after the backend comes up, and then there is no licence to store
anywhere.

The reasons this module does not do that:

- It accepts Dataiku's Free Edition terms as a side effect of a boot, on
  every rebuild, rather than once deliberately.
- The name and email have to reach the boot script, which puts them in
  instance metadata.
- It depends on an undocumented endpoint at boot. If that changes, instances
  come up unlicensed and the reason is several layers down in a cloud-init
  log.

## Reading the admin API key

Separate from licensing, and needed either way. The bootstrap creates an
admin API key at boot and writes it to the path the `api_key_path` output
reports. Getting it off the host takes two SSM calls, because `send-command`
returns a command id rather than the output:

```
./scripts/fetch-key.sh
```

It waits for the file to exist, since DSS answers on its port about half a
minute before the key is written, extracts the key, and checks that it
authenticates before exiting. Needs `enable_ssm = true`, or a `key_name` and
your own SSH.

## Script options

Both scripts take the same optional environment variables:

| Variable | Meaning |
| --- | --- |
| `PROFILE` | AWS CLI profile. Unset uses whatever the CLI resolves on its own. |
| `REGION` | AWS region. Unset likewise. |
| `INSTANCE_ID` | Skip reading `terraform output -raw instance_id`. |

`save-license.sh` also takes `PARAM` (default `/dss/license`), which has to
match the `license_ssm_parameter` you pass the module, and `DATA_DIR` if you
changed the module's `data_dir`.
