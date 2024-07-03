create a 20G disk and start `livecd.iso` in uefi

```bash
qemu-img create -f qcow2 disk.qcow2 20G && \
    qemu-system-x86_64 \
        -enable-kvm \
        -m 4096 \
        -cpu host \
        -smp 2 \
        -bios /usr/share/ovmf/x64/OVMF_CODE.fd \
        -drive file=livecd.iso,format=raw \
        -drive file=disk.qcow2,format=qcow2
```
