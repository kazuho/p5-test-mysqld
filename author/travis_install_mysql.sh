#!/bin/bash
set -ex

if [[ $DATABASE_ADAPTER =~ (mariadb|mysql-5\.[67]) ]]; then
  sudo service mysql stop
  sudo apt-get install python-software-properties
  if [[ $DATABASE_ADAPTER =~ mariadb ]]; then
    sudo apt-key adv --recv-keys --keyserver hkp://keyserver.ubuntu.com:80 0xcbcb082a1bb943db
    sudo add-apt-repository 'deb http://ftp.osuosl.org/pub/mariadb/repo/10.0/ubuntu precise main' ;
    sudo apt-get update
    sudo DEBIAN_FRONTEND=noninteractive apt-get -q --yes --force-yes -f --option DPkg::Options::=--force-confnew install mariadb-server
    sudo apt-get install libmariadbd-dev
  else
    echo mysql-apt-config mysql-apt-config/select-server select $DATABASE_ADAPTER | sudo debconf-set-selections
    wget http://dev.mysql.com/get/mysql-apt-config_0.2.1-1ubuntu12.04_all.deb
    sudo dpkg --install mysql-apt-config_0.2.1-1ubuntu12.04_all.deb
    sudo apt-get update -q
    sudo apt-get install -q -y -o Dpkg::Options::=--force-confnew mysql-server
  fi
  sudo mysql_upgrade
fi
