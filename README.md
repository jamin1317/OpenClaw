# Warning 

- **This is a work in progress.  Nothing here has been tested yet!**

# End Warning



# OpenClaw

One-script deployment of [OpenClaw](https://docs.openclaw.ai) + [Open WebUI](https://github.com/open-webui/open-webui) + [Ollama](https://ollama.com) behind an Nginx reverse proxy. Designed for home lab use on an Ubuntu server.

No programs or containers are stored in this repository — everything is pulled from official sources at install time.

---

## Prerequisites

- A Proxmox VE host (tested on 8.x)
- A machine or VM with at least:
  - 4 CPU cores (8+ recommended for larger models)
  - 8 GB RAM (16+ GB recommended)
  - 40 GB disk (more if you plan to run large LLMs)
- (Optional) GPU passthrough configured in Proxmox for accelerated inference

---

## Step 1: Install Ubuntu on Proxmox

1. **Download the Ubuntu Server ISO**
   - Go to https://ubuntu.com/download/server and download the latest LTS ISO (e.g., 24.04).
   - In Proxmox, navigate to your storage (e.g., `local`) > **ISO Images** > **Upload** and upload the ISO.

2. **Create a new VM**
   - Click **Create VM** in the top-right corner of the Proxmox web UI.
   - **General**: Give it a name (e.g., `openclaw`), pick a VM ID.
   - **OS**: Select the Ubuntu ISO you uploaded.
   - **System**: Defaults are fine. Enable **Qemu Agent** if you want better integration.
   - **Disks**: Set disk size to at least 40 GB (use VirtIO SCSI).
   - **CPU**: Allocate at least 4 cores. Set type to `host` for best performance.
   - **Memory**: Allocate at least 8192 MB (8 GB).
   - **Network**: Use the default bridge (e.g., `vmbr0`).
   - Click **Finish**.

3. **Install Ubuntu**
   - Start the VM and open the console.
   - Walk through the Ubuntu Server installer:
     - Choose your language and keyboard layout.
     - Use the default network configuration (DHCP) or set a static IP.
     - Use the entire disk for installation.
     - Create your user account and password.
     - Enable **Install OpenSSH server** when prompted.
     - Skip additional snaps — the setup script handles everything.
   - Reboot when prompted and remove the ISO from the VM's CD drive.

4. **Note the VM's IP address**
   - After reboot, log in and run:
     ```bash
     ip addr show
     ```
   - Note the IP address (e.g., `192.168.1.100`). You'll use this to SSH in and access the web UI.

---

## Step 2: Download and Run the Setup Script

SSH into your new Ubuntu VM:

```bash
ssh your-username@YOUR_VM_IP
```

Download and run the setup script:

```bash
git clone https://github.com/jamin1317/OpenClaw.git
cd OpenClaw
chmod +x setup.sh
sudo ./setup.sh
```

The script will:
1. Install Docker and Docker Compose
2. Prompt you for configuration (gateway token, passwords, which LLM to download)
3. Generate a `.env` file with your settings
4. Start all four containers (Nginx, OpenClaw, Open WebUI, Ollama)
5. Pull your chosen LLM into Ollama

---

## Step 3: Access Your Services

Once the script completes:

- **Open WebUI**: `http://YOUR_VM_IP` — Chat interface for interacting with LLMs
- **OpenClaw Gateway**: `http://YOUR_VM_IP/openclaw/` — AI agent gateway and runtime
- **Ollama API**: `http://YOUR_VM_IP/ollama/` — Direct model API access

On first visit to Open WebUI, you'll create an admin account. This is local to your instance.

---

## Architecture

```
                    +-------------------+
  Port 80/443 ---->|   Nginx Reverse   |
                    |      Proxy        |
                    +--------+----------+
                             |
           +-----------------+------------------+
           |                 |                  |
  +--------v--------+ +-----v------+  +--------v--------+
  |   Open WebUI    | |  OpenClaw  |  |     Ollama      |
  |   (Port 8080)   | | (Port 18789)| |  (Port 11434)   |
  +--------+--------+ +------------+  +--------+--------+
           |                                    ^
           +------------------------------------+
              Open WebUI talks to Ollama directly
```

Nginx provides a single entry point for browser access. Open WebUI communicates with Ollama over the Docker network.

---

## Managing Your Instance

**Start/stop containers:**

```bash
cd ~/OpenClaw
sudo docker compose up -d      # start
sudo docker compose down        # stop
```

**Pull additional models:**

```bash
sudo docker compose exec ollama ollama pull mistral
sudo docker compose exec ollama ollama pull codellama
```

**View logs:**

```bash
sudo docker compose logs -f              # all containers
sudo docker compose logs -f ollama       # just ollama
sudo docker compose logs -f openclaw     # just openclaw
sudo docker compose logs -f open-webui   # just open webui
```

**Update containers to latest versions:**

```bash
cd ~/OpenClaw
sudo docker compose pull
sudo docker compose up -d
```

---

## Troubleshooting

| Problem | Solution |
|---|---|
| Can't reach the web UI | Check `sudo docker compose ps` — all 4 containers should be running. Check your firewall with `sudo ufw status`. |
| Ollama model download is slow | Large models (13B+) are many GB. Be patient or start with a smaller model like `tinyllama`. |
| Out of memory errors | Reduce model size or increase VM RAM. 7B models need ~4 GB RAM, 13B need ~8 GB. |
| GPU not detected by Ollama | You need to configure GPU passthrough in Proxmox and install the NVIDIA Container Toolkit. See [Ollama Docker GPU docs](https://github.com/ollama/ollama/blob/main/docs/docker.md). |
| OpenClaw gateway unreachable | Verify the container is running and check logs with `sudo docker compose logs openclaw`. |

---

## Files

| File | Purpose |
|---|---|
| `setup.sh` | Interactive setup script — installs prerequisites, configures, and deploys |
| `docker-compose.yml` | Defines the four containers and their networking |
| `nginx/default.conf` | Nginx reverse proxy configuration |
| `.env` | Generated by setup.sh — contains your configuration (git-ignored) |

---

## License

MIT
