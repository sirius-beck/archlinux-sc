# ArchZen

A simple Arch Linux installation script

## For non-NVidia users

I made this script in one afternoon, for my personal use, so currently the script automatically installs only the NVidia GPU drivers, if you use another one, comment out line `257` in the file [post-install.sh](archzen/post-install.sh#L257) and after the installation is complete, install your GPU drivers manually.

Feel free to submit a PR if you want to add this functionality.

## How to use

1. Clone this repository and navigate to the script folder.

   ```bash
   git clone https://github.com/sirius-beck/archzen.git && cd archzen/archzen
   ```

2. Configure the installation in the [config.sh](archzen/config.sh) file.

3. Run the [install.sh](archzen/install.sh) file.

   ```bash
   chmod +x ./install.sh && ./install.sh
   ```

4. The [post-install.sh](archzen/post-install.sh) file will be automatically executed when necessary.
