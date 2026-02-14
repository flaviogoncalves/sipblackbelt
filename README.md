# SIP Blackbelt - OpenSIPS Installation & Demo Files

Automated installation scripts and demo recordings for **OpenSIPS 3.6** on Debian 12, created as part of the **SIP Blackbelt Certification**.

With a single command, you get a fully working OpenSIPS environment — ready for SIP routing, authentication, NAT traversal, and management through the Control Panel.

## Quick Install (OpenSIPS 3.6)

On a fresh **Debian 12 (Bookworm)** server, run:

```bash
curl -sSL https://raw.githubusercontent.com/flaviogoncalves/sipblackbelt/main/opensips_install.sh | sudo bash
```

This sets up a complete environment in minutes:

- OpenSIPS 3.6 with CLI and all modules
- MariaDB with the OpenSIPS database
- Apache + PHP + OpenSIPS Control Panel 9.3.5
- Residential routing script (authentication, DB user location, NAT traversal)
- RTPProxy for media relay
- Pre-configured SIP users ready to make calls

## Contents

| File | Description |
|------|-------------|
| `opensips_install.sh` | Complete OpenSIPS 3.6 installation script |
| `osips_install_rec.sh` | Installation demo recording script |
| `osips_script_demo.sh` | OpenSIPS script walkthrough demo |
| `osipscp_install_demo.sh` | Control Panel installation demo |
| `opensips_install_demo.cast` | asciinema recording — installation |
| `opensips_script_demo.cast` | asciinema recording — script walkthrough |
| `opensips_cp_demo.cast` | asciinema recording — control panel |

## Requirements

- Debian 12 (Bookworm)
- Root or sudo access
- Internet connectivity

## SIP Blackbelt Certification

These files are part of the **SIP Blackbelt Certification** — a hands-on program where you master SIP and OpenSIPS from the ground up. The course covers everything from SIP fundamentals to advanced routing, high availability, load balancing, and real-world VoIP deployments.

Whether you're a telecom engineer looking to deepen your skills or a developer building voice infrastructure, the SIP Blackbelt gives you the practical knowledge to design, deploy, and troubleshoot production SIP platforms with confidence.

**Learn more and enroll at [sipblackbelt.com](https://voip.school)**

## License

These materials are part of the SIP Blackbelt Certification. All rights reserved.
