# CloudFlare Scripts

Automation scripts for managing and interacting with the **Cloudflare API**. This repository contains operational tooling for DNS management, firewall rules, SSL/TLS settings, caching, analytics, and other Cloudflare services.

Primary language: **PowerShell**

---

## 📊 Status & Info

![Last Commit](https://img.shields.io/github/last-commit/BlindTrevor/CloudFlare-Scripts)
![Issues](https://img.shields.io/github/issues/BlindTrevor/CloudFlare-Scripts)
![Repo Size](https://img.shields.io/github/repo-size/BlindTrevor/CloudFlare-Scripts)

---

## 🚀 Overview

This repo centralizes repeatable tasks, bulk operations, reporting, and automation for Cloudflare zones, records, and security configurations.

---

## 🔐 Security & Secrets

- **Never** commit API tokens, keys, or export sensitive zone data.
- Use a **secrets manager** (e.g., 1Password, Azure Key Vault, or environment variables).
- Scripts should read secrets via environment variables or inject them at runtime.
- If logs may contain sensitive data (e.g., IP addresses), write to a secure path and restrict permissions.

---

## ⚠️ Disclaimer

These scripts are provided as-is. Test in a **non-production** environment first and apply the principle of least privilege. Some API endpoints may require elevated permissions.
