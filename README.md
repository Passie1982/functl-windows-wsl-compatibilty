# functl Windows/WSL-compatibiliteit

Hulpscript dat [`functl`](https://docs.fundament-poc.nl/docs/user/functl) — de
command-line client voor de [Fundament](https://docs.fundament-poc.nl/) platform-API — verbindt
met een native Windows-workflow. `functl` biedt alleen kant-en-klare binaries voor Linux en macOS,
dus op Windows moet het binnen WSL draaien. Deze repo bevat
[Setup-FundamentKubeconfig.ps1](Setup-FundamentKubeconfig.ps1), een PowerShell-script dat `functl`
in WSL installeert, het beschikbaar maakt voor Windows-tools zoals `kubectl`, OpenLens en Freelens,
en een door Fundament aangeleverde kubeconfig samenvoegt met je standaard kubeconfig.

## Achtergrond

`functl` authenticeert bij het Fundament-platform via een API-sleutel en biedt onder andere:

- `functl auth` — login, status, logout
- `functl org` — organisatie tonen/instellen/loskoppelen, leden beheren
- `functl project` — projecten tonen/ophalen/aanmaken/bijwerken, leden beheren
- `functl namespace` — namespaces tonen/aanmaken/verwijderen
- `functl cluster` — clusters tonen/ophalen, `kubeconfig` genereren, kortlevende `token` aanmaken
- `functl apikey` — API-sleutels tonen/aanmaken/intrekken/verwijderen
- `functl config` — configuratiemap/-pad tonen
- `functl version`

Voor clustertoegang schrijft `functl cluster kubeconfig` een kubeconfig waarvan de `exec`-
credential-plugin bij elk `kubectl`-verzoek `functl cluster token` aanroept om je opgeslagen
API-sleutel om te wisselen voor een kortlevend token. Dit betekent dat `functl` geïnstalleerd,
geauthenticeerd en bereikbaar moet blijven bij elk gebruik van `kubectl` (of een tool die dezelfde
kubeconfig gebruikt, zoals OpenLens/Freelens) — niet alleen eenmalig tijdens de installatie.

Op Windows is `functl` niet native beschikbaar, dus dit script installeert het binnen een
WSL-distro en maakt een kleine Windows-side wrapper aan zodat de Windows-`kubectl`/`PATH` het
transparant via WSL kan aanroepen.

## Wat `Setup-FundamentKubeconfig.ps1` doet

1. **Controleert vereisten** — checkt of het opgegeven kubeconfig-bestand bestaat, of `kubectl`
   op de Windows-`PATH` staat, en of de doel-WSL-distro is geïnstalleerd.
2. **Installeert `functl` in WSL** — detecteert de WSL-architectuur (`x86_64`/`aarch64`) en
   downloadt de bijbehorende release van de `functl-latest` GitHub-release naar `~/.local/bin`
   (geen `sudo` nodig). Wordt overgeslagen als `functl` al is geïnstalleerd, tenzij `-Force` is
   opgegeven.
3. **Controleert `functl`-authenticatie** — draait `functl auth status` in WSL en toont een
   herinnering om interactief `functl auth login` uit te voeren als er nog niet is
   geauthenticeerd.
4. **Maakt een Windows-wrapper** — schrijft `%USERPROFILE%\bin\functl.cmd`, die elk commando
   doorstuurt naar `wsl.exe -d <distro> -- functl`, en voegt die map toe aan de gebruikers-`PATH`
   zodat Windows-tools (de exec-plugin van kubectl, OpenLens, Freelens, enz.) `functl` kunnen
   vinden.
5. **Voegt de kubeconfig samen** — maakt een back-up van een eventuele bestaande
   `%USERPROFILE%\.kube\config`, voegt deze samen met de van het Fundament-portaal gedownloade
   kubeconfig via `kubectl config view --flatten`, en schrijft het resultaat terug als standaard
   kubeconfig.
6. **Toont een samenvatting** — geeft de beschikbare contexten in de samengevoegde kubeconfig weer.

## Gebruik

```powershell
.\Setup-FundamentKubeconfig.ps1 -KubeconfigPath "C:\Users\<jij>\Downloads\kubeconfig-<org>-<cluster>.yaml"
```

### Parameters

| Parameter         | Verplicht | Standaard | Beschrijving                                                                 |
|-------------------|-----------|-----------|--------------------------------------------------------------------------------|
| `KubeconfigPath`  | Ja        | —         | Pad naar de kubeconfig die is gedownload van het Fundament-portaal.            |
| `WslDistro`       | Nee       | `Ubuntu`  | Naam van de WSL-distro waarin `functl` moet worden geïnstalleerd/uitgevoerd.    |
| `Force`           | Nee       | `false`   | Installeert `functl` opnieuw in WSL, ook als het al aanwezig is.                |

### Voorbeeld

```powershell
.\Setup-FundamentKubeconfig.ps1 `
  -KubeconfigPath "C:\Users\SomeUser\Downloads\kubeconfig-downloaded-from-the-fundament-console.yaml" `
  -WslDistro "Ubuntu-22.04" `
  -Force
```

## Vereisten

- Windows met WSL en een werkende Linux-distro geïnstalleerd (standaard `Ubuntu`).
- `kubectl` geïnstalleerd en beschikbaar op de Windows-`PATH`.
- Een kubeconfig-bestand gedownload van de Fundament-console voor het doelcluster.
- Netwerktoegang vanuit WSL naar GitHub (voor het downloaden van de `functl`-release) en naar de
  Fundament-API.

## Na het uitvoeren van het script

Als `functl` nog niet was geauthenticeerd, log dan eenmalig interactief in en voer het script
opnieuw uit (of voer gewoon `kubectl` opnieuw uit, aangezien de wrapper altijd via WSL werkt):

```powershell
wsl -d Ubuntu -- functl auth login
```

Controleer of alles correct is ingesteld:

```powershell
functl version
kubectl config get-contexts
kubectl get nodes
```

## Opmerkingen

- De Windows-wrapper (`functl.cmd`) stuurt alle argumenten simpelweg door naar
  `wsl.exe -d <distro> -- functl`, waardoor de credentials en configuratie van `functl`
  (`~/.config/fundament/`) binnen WSL blijven, niet aan de Windows-kant.
- Het script maakt een back-up van je bestaande `~/.kube/config` (als `config.bak-<timestamp>`)
  vóór het samenvoegen, zodat eerder geconfigureerde contexten bewaard blijven.
- Zie de [functl CLI-documentatie](https://docs.fundament-poc.nl/docs/user/functl) en
  [Cluster access](https://docs.fundament-poc.nl/docs/user/clusters#cluster-access) voor meer
  details over authenticatie, configuratie en de `functl`-commandoreferentie.
