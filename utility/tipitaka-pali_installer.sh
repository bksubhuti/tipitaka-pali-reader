#!/bin/bash

basename=tipitaka_pali_reader
appimages=${basename}.AppImage
icons=${basename}.png
desktopfile=${basename}.desktop
tpr_dep="libsqlite3-dev fuse"   

install_dep(){
if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi
for app_dep in ${tpr_dep}
do
  sudo dpkg -s $app_dep &> /dev/null  

    if [ $? -ne 0 ]

        then
            echo "not installed"  
            sudo apt-get update
            sudo apt-get install $name

        else
            echo    "$app_dep installed"
    fi
done
}

# System
# desktopdir=/usr/share/applications/
# appdir=/usr/local/bin/
# iconsdir=/usr/share/icons/

cat > $desktopfile <<EOF
[Desktop Entry]
Name=Tipitaki Pali Reader
# Name[my]=.
# Name[th]=.
# Name[zh]=.
# Name[vi]=.
Comment=A Modern Application for Reading Pali
# Comment[my]=.
# Comment[th]=.
# Comment[zh]=.
# Comment[vi]=.
Exec=${HOME}/.local/bin/tipitaka_pali_reader.AppImage
Terminal=false
Type=Application
Icon=${HOME}/.local/share/icons/tipitaka_pali_reader.png
StartupWMClass=Tipitaki Pali Reader
Categories=Utility;Education;
Keywords=Pali;Reader;Dictionary;Dhamma;Tipitaka
EOF

# User
desktopdir=~/.local/share/applications/
appdir=~/.local/bin/
iconsdir=~/.local/share/icons/

chmod +x $appimages $desktopfile
# cp -v $appimages $appdir
# cp -v $icons $iconsdir
cp -v $desktopfile $desktopdir

install_dep

# application-desktop file with commands
# desktop-file-install tipitaka_pali_reader.desktop  --dir=$HOME/.local/share/applications  
# update-desktop-database -q

# application to menu fav bar
# application="'${basename}.desktop'"
# favourites="/org/gnome/shell/favorite-apps"
# dconf write ${favourites} \
#     "$(dconf read ${favourites} \
#     | sed "s/, ${application}//g" \
#     | sed "s/${application}//g" \
#     | sed -e "s/]$/, ${application}]/")"
