# SMB Mount Cheatsheet (per-OS)

## macOS (Darwin)

### Mount read-only

```bash
mkdir -p ~/mnt/{share-name}
mount_smbfs -o nobrowse,ro //user@host/share ~/mnt/{share-name}
```

Flags:
- `-o nobrowse` — don't show in Finder sidebar
- `-o ro` — read-only

Credentials come from Keychain if the share was previously connected via
Finder → Connect to Server (⌘K). Keychain entries are managed by the user;
this skill never writes to them.

For Kerberos:

```bash
kinit user@REALM
mount_smbfs -o nobrowse,ro //host/share ~/mnt/{share-name}
```

### Unmount

```bash
umount ~/mnt/{share-name}
# Fallback if the share is busy:
diskutil unmount force ~/mnt/{share-name}
```

## Linux

### Option A — CIFS mount (needs root, cifs-utils package)

```bash
sudo mkdir -p /mnt/{share-name}
sudo mount -t cifs -o ro,vers=3.0,sec=krb5,username=$USER \
  //host/share /mnt/{share-name}
```

For credentials file instead of Kerberos:

```bash
# User creates ~/.smbcredentials (chmod 600):
#   username=alice
#   password=...
sudo mount -t cifs -o ro,credentials=/home/$USER/.smbcredentials \
  //host/share /mnt/{share-name}
```

Unmount:

```bash
sudo umount /mnt/{share-name}
```

### Option B — gvfs (userland, no root)

```bash
gvfs-mount "smb://host/share"
# Files appear under /run/user/$UID/gvfs/smb-share:server=host,share=share/
```

Unmount:

```bash
gvfs-mount -u "smb://host/share"
```

## Windows

No mount step needed. UNC paths are first-class:

```powershell
Get-ChildItem -Path "\\host\share" -Recurse -Depth $Depth -File
Copy-Item -Path "\\host\share\file.docx" -Destination "docs\ato-package\..."
```

Credentials flow:
- Current logged-in user token (default)
- Or previously saved via `cmdkey /add:host /user:DOMAIN\user /pass:...`
  (user manages this, not the skill)

Check access with:

```powershell
Test-Path "\\host\share"
```

## Kerberos helpers (all OSes)

```bash
kinit user@REALM        # Obtain ticket
klist                   # Verify ticket present
kdestroy                # Clear tickets (only if the user asks)
```

This skill never calls `kinit` or `kdestroy` — it only calls `klist` to
probe whether a ticket exists.

## Forbidden operations

- `cp` files TO a mount point
- `mkdir` on a mount point
- `chmod`, `chown` on mount point contents
- `rm`, `mv` of mount point contents
- Writing to `~/.smbcredentials` (user-managed)
- Calling `kinit` or `kdestroy`
- Mounting read-write (always pass `ro`)
