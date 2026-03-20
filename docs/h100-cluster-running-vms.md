# H100 Cluster — VMs by Organization

Generated: 2026-03-06 (post-cleanup)

Cluster: 6-node Proxmox cluster, all **NVIDIA H100 SXM5 80GB** nodes.

## Summary

| Metric | Value |
|---|---|
| Total organizations | 15 |
| Total VMs (on Proxmox) | 23 |
| Running | 4 |
| Stopped | 19 |
| Storage on NFS (`tensordock_vast_data`) | 22 VMs |
| Storage on Ceph RBD (`tensordock_data`) | 1 VM |

---

## Ai-model-training

**Org UUID:** `1cac3e6e-860c-49bf-8e27-21a5a9fdda88`

| VM Name | VM UUID | Proxmox VMID | Status | Node | Storage | Format | Disk Size |
|---|---|---|---|---|---|---|---|
| qr-code-delivery | `1854338b-755e-429e-bb12-b3978ba4c4c4` | 18765025 | Stopped | b3f9c2a6 (159.26.86.125) | NFS | raw | 550G |

---

## Air Flows Data Platform, S.L.

**Org UUID:** `1ec15a08-4752-4013-b363-af6634cc46fa`

| VM Name | VM UUID | Proxmox VMID | Status | Node | Storage | Format | Disk Size |
|---|---|---|---|---|---|---|---|
| inference_anh | `1a42e783-f05c-41aa-ab47-261af50a3f45` | 11586572 | Stopped | a2e8b1f5 (159.26.86.124) | NFS | raw | 200G |

---

## Babu P Alluri

**Org UUID:** `eca28a2a-41b9-4669-bcd6-d5243b1dc456`

| VM Name | VM UUID | Proxmox VMID | Status | Node | Storage | Format | Disk Size |
|---|---|---|---|---|---|---|---|
| My CPU Server (Intel Xeon Platinum 8470) | `979f8203-0536-4be7-98d2-35011fc6846c` | 17932276 | **Running** | b3f9c2a6 (159.26.86.125) | NFS | raw | 600G |

---

## Daniel Semler

**Org UUID:** `c1d7a32f-2fa9-4c09-99fe-dcf5d3f37873`

| VM Name | VM UUID | Proxmox VMID | Status | Node | Storage | Format | Disk Size |
|---|---|---|---|---|---|---|---|
| My CPU Server (Intel Xeon Platinum 8470) | `fff0e71d-8de7-4f8f-bc6b-ef4c9ab9f153` | 13373549 | Stopped | a2e8b1f5 (159.26.86.124) | NFS | raw | 200G |

---

## David Jones

**Org UUID:** `81ab16d7-6b8a-49a0-8d2d-3e4e10f45116`

| VM Name | VM UUID | Proxmox VMID | Status | Node | Storage | Format | Disk Size |
|---|---|---|---|---|---|---|---|
| cv03 | `7a548179-926f-4586-811c-e83b0bf26416` | 821488945 | Stopped | a7f8e3d1 (159.26.86.124) | NFS | raw | 250G |
| CVS-02 | `f91add32-d685-4b4c-9200-bee8bd195dec` | 833759054 | Stopped | a7f8e3d1 (159.26.86.124) | NFS | raw | 250G |

---

## Guy Ibambasi

**Org UUID:** `9f331a31-0471-4f80-8c0b-171471b817d8`

| VM Name | VM UUID | Proxmox VMID | Status | Node | Storage | Format | Disk Size |
|---|---|---|---|---|---|---|---|
| My Tensordock Server | `28523f22-0dc6-40f7-98b7-aa22e763988c` | 15218685 | Stopped | b3f9c2a6 (159.26.86.125) | NFS | raw | 100G |

---

## Laetro

**Org UUID:** `5dd8a45e-940d-407b-b956-9ea31fa388aa`

| VM Name | VM UUID | Proxmox VMID | Status | Node | Storage | Format | Disk Size |
|---|---|---|---|---|---|---|---|
| My Tensordock Server | `b41caec6-19e4-434b-90ad-46e4e781228d` | 11164964 | Stopped | 5b59074a (159.26.86.116) | **Ceph RBD** | rbd | 200G |

---

## Minu Chung

**Org UUID:** `c759314b-6751-481e-8614-1911a379611f`

| VM Name | VM UUID | Proxmox VMID | Status | Node | Storage | Format | Disk Size |
|---|---|---|---|---|---|---|---|
| aicompiler | `6a5b53c6-9d04-4363-9853-e570bb1f8e76` | 854270706 | Stopped | b3f9c2a6 (159.26.86.125) | NFS | raw | 2000G |

---

## Nihal Shah

**Org UUID:** `1c65162c-677d-476f-ab9c-0f0745cc2904`

| VM Name | VM UUID | Proxmox VMID | Status | Node | Storage | Format | Disk Size |
|---|---|---|---|---|---|---|---|
| My Tensordock Server | `31da2302-d2aa-43b0-8df7-2a37ef333ca9` | 17020490 | Stopped | 5b59074a (159.26.86.116) | NFS | raw | 100G |

---

## Niket Patel

**Org UUID:** `4058359a-3ccb-4dd7-abb1-283621330533`

| VM Name | VM UUID | Proxmox VMID | Status | Node | Storage | Format | Disk Size |
|---|---|---|---|---|---|---|---|
| My Tensordock Server | `1c24e2b8-2f24-4dc9-aea3-f41516143f81` | 15088669 | Stopped | 5b59074a (159.26.86.116) | NFS | raw | 100G |
| My Tensordock Server | `bb425fe1-7e50-4a88-afb4-d95361153e9c` | 15289107 | Stopped | a2e8b1f5 (159.26.86.124) | NFS | raw | 100G |
| My Tensordock Server 2 | `03be7c3c-64e0-47ea-91bb-e69880ff21be` | 13595318 | Stopped | a2e8b1f5 (159.26.86.124) | NFS | raw | 100G |

---

## qeg qeg

**Org UUID:** `cfa57bd5-148c-4392-941a-7147cec06711`

| VM Name | VM UUID | Proxmox VMID | Status | Node | Storage | Format | Disk Size |
|---|---|---|---|---|---|---|---|
| ml | `b8037d4b-38bd-465e-92e9-c00bcbe3c630` | 850249345 | **Running** | b3f9c2a6 (159.26.86.125) | NFS | raw | 500G |

---

## Shushank Singh

**Org UUID:** `4b5b98dd-f796-47e2-85b6-9aed402b7d0f`

| VM Name | VM UUID | Proxmox VMID | Status | Node | Storage | Format | Disk Size |
|---|---|---|---|---|---|---|---|
| My Tensordock Server | `daa4de66-272b-483e-a702-f829084a3099` | 887742961 | Stopped | a7f8e3d1 (159.26.86.124) | NFS | raw | 100G |

---

## Simon Byrd

**Org UUID:** `e7786bc4-7c16-4628-b452-16a18bbd6c1f`

| VM Name | VM UUID | Proxmox VMID | Status | Node | Storage | Format | Disk Size |
|---|---|---|---|---|---|---|---|
| My CPU Server (Intel Xeon Platinum 8470) | `8fc701b2-7999-41fb-b4ed-1353aa5a315b` | 13325156 | **Running** | b3f9c2a6 (159.26.86.125) | NFS | raw | 550G |

---

## Spark Team

**Org UUID:** `a269a4c1-e73d-4fb4-bc42-6cb9285fdd15`

| VM Name | VM UUID | Proxmox VMID | Status | Node | Storage | Format | Disk Size |
|---|---|---|---|---|---|---|---|
| HARD | `a48103d6-dd78-4a38-a22d-d6ea3dec4d84` | 805661243 | Stopped | a7f8e3d1 (159.26.86.124) | NFS | raw | 400G |

---

## SuDo Research Management Limited

**Org UUID:** `411072f5-47e5-4bd3-be42-c6a90290b0ac`

| VM Name | VM UUID | Proxmox VMID | Status | Node | Storage | Format | Disk Size |
|---|---|---|---|---|---|---|---|
| sn34-t1 [MIGRATION-CLONE-NOT-READY-FOR-USE] | `1b998cb7-0dba-4824-ad0a-d2b96be96d5f` | 15386265 | Stopped | 5b59074a (159.26.86.116) | NFS | raw | 250G |
| sn34-t2 [MIGRATION-CLONE-NOT-READY-FOR-USE] | `164af88d-5430-4ccd-a011-1716b8bc9066` | 19725213 | Stopped | 5b59074a (159.26.86.116) | NFS | qcow2 | 350G |

---

## Tim R

**Org UUID:** `d394a962-edd6-4338-9a92-75e0b54c396c`

| VM Name | VM UUID | Proxmox VMID | Status | Node | Storage | Format | Disk Size |
|---|---|---|---|---|---|---|---|
| image_gen | `098cdeee-c23d-4a65-839c-28247328e81d` | 813520207 | Stopped | b3f9c2a6 (159.26.86.125) | NFS | raw | 200G |

---

## Ubitec GmbH

**Org UUID:** `a232e121-bd41-4f10-8d80-3b5cacad50e6`

| VM Name | VM UUID | Proxmox VMID | Status | Node | Storage | Format | Disk Size |
|---|---|---|---|---|---|---|---|
| h100-test | `484cf02b-3d1e-460a-99e1-0916f9bd96fa` | 885775653 | Stopped | b3f9c2a6 (159.26.86.125) | NFS | raw | 1000G |

---

## Zillion Network

**Org UUID:** `9e660082-2af8-44bc-a68b-352cc93a376f`

| VM Name | VM UUID | Proxmox VMID | Status | Node | Storage | Format | Disk Size |
|---|---|---|---|---|---|---|---|
| My Tensordock Server | `23e93310-6a0b-43ce-aa22-2a6bcefd3b7b` | 13872335 | **Running** | a7f8e3d1 (159.26.86.124) | NFS | qcow2 | 4800G |
| My Tensordock Server | `2aa82221-4911-4d78-adbf-d864b700a243` | 10772335 | **Running** | a7f8e3d1 (159.26.86.124) | NFS | qcow2 | 2400G |

---

## Destroyed VMs (removed this session)

18 VMs across 7 organizations were terminated on 2026-03-06:

| Org | VM Name | VM UUID | Proxmox VMID | Notes |
|---|---|---|---|---|
| Abbas Zaidi | 2x GPU VM (1) | `95809c3a` | 17636406 | Ceph RBD disk orphans |
| Abbas Zaidi | 2x GPU VM (2) | `753b8d38` | 11615490 | Ceph RBD disk orphans |
| Cleat.ai | Cleat-Server-1 | `7276f6a4` | 19957115 | Ceph RBD disk orphans |
| Cleat.ai | Cleat-Server-2 | `b69f1f7c` | 12230226 | Ceph RBD disk orphans |
| Cleat.ai | Cleat-Server-3 | `d4fdfaee` | 15909698 | Ceph RBD disk orphans |
| Cleat.ai | Cleat-Server-4 | `5188207d` | 12312190 | Ceph RBD disk orphans |
| Cleat.ai | Sherman VM or smth idfk | `6856077c` | 110 | Clean |
| erich mayne | EOS | `fffd61dc` | 15472670 | Clean |
| Ian | My Tensordock Server | `510e05a6` | 15725709 | Clean |
| Ignacio Arzaut | My Tensordock Server | `1d73e6f8` | 806277859 | Clean |
| Ragha Prasad | kunwar | `5596f840` | 14865193 | Clean |
| Ragha Prasad | 493fd3cf-k3s-master | `19ca719f` | 16814945 | Clean |
| Ragha Prasad | 9c2f8476-k3s-master-node | `2adba4e0` | 10816817 | Clean |
| Ragha Prasad | 9c2f8476-k3s-worker-node | `5f09fbe2` | 17900118 | Clean |
| Ragha Prasad | cea17e5c-k3s-master | `4febaad7` | 14542730 | Clean |
| Ragha Prasad | cea17e5c-k3s-worker | `5e44a7c1` | 12669736 | Clean |
| Ragha Prasad | d3a70d10-... | `d3a70d10` | 16967669 | Clean |
| TensorDock | RUDCS-H100-1 | `2da6408d` | 19040381 | Clean |

---

## Node Reference

| Node UUID (short) | Public IP | Internal IP | GPU |
|---|---|---|---|
| 5b4abeaa | 159.26.86.115 | 10.5.58.3 | H100 SXM5 80GB |
| 5b59074a | 159.26.86.116 | 10.5.58.4 | H100 SXM5 80GB |
| a2e8b1f5 | 159.26.86.124 | 10.5.58.12 | H100 SXM5 80GB |
| a7f8e3d1 | 159.26.86.124 | 10.5.58.6 | H100 SXM5 80GB |
| b3f9c2a6 | 159.26.86.125 | 10.5.58.13 | H100 SXM5 80GB |
| b4e9f2a8 | 159.26.86.123 | 10.5.58.7 | H100 SXM5 80GB |

## Notes

- **Running VMs** are shown in **bold** status. Only 4 remain running: Babu P Alluri, qeg qeg, Simon Byrd, and Zillion Network (2 VMs).
- **Ceph RBD:** Only 1 VM remains on Ceph RBD (Laetro, stopped). Ceph is still degraded.
- **NFS VMs (22):** All other VMs are on the shared NFS mount (`tensordock_vast_data` at `10.5.69.1:/data`).
- **Zillion Network** still has the largest footprint: 4.8TB + 2.4TB = **7.2TB provisioned**.
- **DB records not cleaned:** The destroyed VMs still appear in the Supabase database with their original status. Only the Proxmox configs and disks (where possible) were removed.
- **Ceph RBD orphaned disks:** 6 destroyed VMs had Ceph RBD disks that couldn't be deleted due to the degraded cluster. Clean up with `rbd rm tensordock_data/vm-<vmid>-disk-*` once Ceph recovers.
