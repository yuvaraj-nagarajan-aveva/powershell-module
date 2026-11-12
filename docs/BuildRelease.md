# Build and release

1. Update `ModuleVersion` in `UVModule.psd1`, commit the change, and push it.
   Each release needs a new version; published versions are immutable.
2. Create and push a matching tag, for example:

   ```powershell
   git tag v0.1.0
   git push origin v0.1.0
   ```

3. The GitHub Actions workflow runs the tests, checks that the tag matches the
   manifest, builds the package, and publishes it using `GITHUB_TOKEN` with
   package write permission. Check the workflow result and package visibility
   before installing. Repository or organization policies may need to permit
   Actions to publish packages. For an existing package, grant the workflow
   repository package access if needed.

After the first release, check the package's visibility in GitHub Package
settings. If it is private, change it to public there. GitHub warns that once a
package is public, it cannot be made private again. Public GitHub Packages still
require authentication to install; this is not a PowerShell Gallery release.

To build without publishing, run the following from the repository root with
PSResourceGet 1.1.0 or later installed:

```powershell
New-Item -ItemType Directory -Path .\package -Force | Out-Null
.\scripts\Build-ModulePackage.ps1 -DestinationPath .\package
```

If publication fails before the version exists, rerun the workflow after
correcting the cause. If the package version was already published, verify it
before deciding whether to publish a new version. To roll back, install a
known-good version explicitly with `Install-PSResource -Version <version>`.

The package installation/update integration test is intended for a disposable
environment with no existing `UVModule` installation, because it temporarily
installs and removes test versions for the current user.
