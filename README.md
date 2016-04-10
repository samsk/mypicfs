# myPicfs

myPicfs is FUSE filesystem wrapper written in perl for local Picasa folders. This it is possible to expose i.e. Picasa starred photos on network via samba or dlna.

**This  project is dead, it has been superseeded by go-mypicfs to improve performance.**

## Mounting

Usage is easy, simply mount directory with your picasa images (i.e. */media/ARCHIVE/photos*) to some mount point (i.e. */media/PHOTOS*).

```bash
$ mypicfs -type=picasa /media/ARCHIVE/photos /media/PHOTOS/
```

## Features

- *Starred photos* per subdirectory 
- *Global Starred photos* for all subfolders divided by year

## Planned features

- **NONE**

## Dependencies

- **FUSE** module

## Notice

- Only **.picasa.ini** files are recognized and interpreted, you should rename all existing **Picasa.ini** files to make them work.
