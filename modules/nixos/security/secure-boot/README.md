### handling /etc/secureboot

see:

- https://stackoverflow.com/a/54908072
- https://www.gnu.org/software/tar/manual/html_section/Reproducibility.html

try:

```shell
sudo tar --sort=name --format=posix --pax-option='delete=atime,delete=ctime' -czf - -C /etc/secureboot . | tar -ztvf -
```

backup:

```shell
sudo tar --sort=name --format=posix --pax-option='delete=atime,delete=ctime' -czf - -C /etc/secureboot . | pass insert --multiline --force secure-boot/etc-secureboot.tar.gz
```

list backup:

```shell
pass show secure-boot/etc-secureboot.tar.gz | tar -ztvf -
```

restore locally:

```shell
sudo mkdir -p /etc/secureboot
sudo chmod 0755 /etc/secureboot
pass show secure-boot/etc-secureboot.tar.gz | sudo tar -zxf - -C /etc/secureboot
```

restore remotely:

```shell
ssh etra.lan. sudo mkdir -p /etc/secureboot
ssh etra.lan. sudo chmod 0755 /etc/secureboot
pass show secure-boot/etc-secureboot.tar.gz | ssh etra.lan. sudo tar -zxf - -C /etc/secureboot
```