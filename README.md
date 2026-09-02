# goEMM

A memory for AI assistants that lives on your own computer.

Your assistants read from it and write to it, so what you settled last week is
still there next week — in a database file you own, that nothing sends
anywhere. There is no account, and goEMM never reports what you store, what you
search for, or that you are running it.

**This repository holds builds, not source.** Nothing here is compiled from
anything in it.

---

## Install

### macOS and Linux — in Terminal

```bash
curl -fsSL https://raw.githubusercontent.com/tkraljevic/goEMM/main/install.sh | sh
```

### Windows — in Command Prompt

Not the Terminal line above: Windows has no `sh`, and pasting it there
answers `'sh' is not recognized`. This one:

```bat
curl -fsSL -o "%TEMP%\emm-install.bat" https://raw.githubusercontent.com/tkraljevic/goEMM/main/install.bat && "%TEMP%\emm-install.bat"
```

`curl` has shipped with Windows since version 1803, so nothing needs
installing first.

<details>
<summary>PowerShell, if you prefer it</summary>

```powershell
irm https://raw.githubusercontent.com/tkraljevic/goEMM/main/install.ps1 | iex
```

If that is refused, it is the execution policy rather than goEMM. The Command
Prompt line above sidesteps that question entirely, which is why it is the one
offered first.
</details>

It works out which build your machine needs, checks the download against the
published checksums, and refuses to install a binary that will not run. If
anything is wrong it stops and says so; it does not install half of anything.

goEMM lands in `~/.emm` (`%USERPROFILE%\.emm` on Windows).

### If you already have goEMM

The installer refuses to write over an existing copy and points you at the
updater, which is usually what you want:

```bash
emm update
```

To install over it anyway, add `--force`. That replaces the program only — your
memories are a separate file and are not touched. It does not update the tray,
so run `emm update` afterwards for that.

```bash
curl -fsSL https://raw.githubusercontent.com/tkraljevic/goEMM/main/install.sh | sh -s -- --force
```

```bat
curl -fsSL -o "%TEMP%\emm-install.bat" https://raw.githubusercontent.com/tkraljevic/goEMM/main/install.bat && "%TEMP%\emm-install.bat" --force
```

**On Windows, stop goEMM first.** Windows will not replace a file that is open,
and the tray usually has it running:

```bat
emm http stop
```

Quit it from the system tray too, if it is there. The installer says so if it
runs into a locked file, rather than leaving you with the message Windows gives,
which names no process.

---

## First run

```bash
emm demo          # see what it does, on a throwaway database
emm setup         # connect your AI assistants
emm setup path    # so you can type 'emm' from anywhere
```

`emm demo` touches nothing real. It stores a few example notes in a temporary
database and searches them, so you can see the thing work before letting it
near your tools.

Then open the dashboard:

```bash
emm http start
```

It serves on `http://127.0.0.1:4599`, on your machine only. The first sign-in is
`admin` / `admin` and it will keep saying so until you change it.

---

## Security warnings on first run

**The binaries are not signed.** Code-signing certificates cost money every year
and goEMM has not bought one yet, so your operating system does not recognise
the publisher and says so. That warning is accurate: it means "we cannot tell
you who made this", not "this is known to be bad".

- **macOS.** The installer clears the quarantine flag, so an install through
  the command above runs without a dialog. A binary you download by hand from
  the Releases page will be quarantined — right-click it, choose Open, and
  confirm once.
- **Windows.** SmartScreen may show "Windows protected your PC". Choose **More
  info → Run anyway**. The installer clears the download marker for the file it
  places, so this usually appears only for hand-downloaded files.

If you would rather check for yourself than trust either of us, verify the
download against the release's `SHA256SUMS.txt`:

```bash
shasum -a 256 emm-darwin-arm64          # macOS
sha256sum emm-linux-amd64               # Linux
```

```powershell
Get-FileHash -Algorithm SHA256 emm-windows-amd64.exe
```

The installer does exactly this before putting anything in place. Doing it by
hand only tells you the same thing twice — which is the point of publishing the
sums.

---

## Updating

goEMM updates itself and keeps a copy of the version it replaces, so an update
that goes badly is one command to undo:

```bash
emm update
emm update check      # is there anything new?
emm update rollback   # go back to the copy it kept
```

---

## Uninstalling

```bash
emm uninstall
```

It removes the program, the tray and what it registered with your AI clients,
and asks before touching anything. **Your memories are left alone** — they are
in `~/.emm/memory.db`, which is yours. Delete that file yourself if you want
them gone.

---

## Which build is which

| file | for |
| --- | --- |
| `emm-darwin-arm64` | Mac with Apple Silicon (M1 and later) |
| `emm-darwin-amd64` | Mac with an Intel processor |
| `emm-linux-amd64` | Linux on a normal PC processor |
| `emm-linux-arm64` | Linux on ARM — a Raspberry Pi, an ARM server |
| `emm-windows-amd64.exe` | Windows on a normal PC processor |
| `emm-windows-arm64.exe` | Windows on ARM |

`emm-tray-*` is the small launcher that puts goEMM in the menu bar or system
tray. The installer does not fetch it; `emm install tray` does, once goEMM is
in place.

`SHA256SUMS.txt` carries a checksum for every file in that release.
