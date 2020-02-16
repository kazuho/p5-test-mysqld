#!/bin/bash
set -ex

if [[ $DATABASE_ADAPTER =~ (mariadb|mysql-(5\.[567]|8\.0)) ]]; then
  sudo service mysql stop
  sudo apt-get install python-software-properties
  if [[ $DATABASE_ADAPTER =~ mariadb ]]; then
    sudo apt-key adv --recv-keys --keyserver hkp://keyserver.ubuntu.com:80 0xcbcb082a1bb943db
    sudo add-apt-repository 'deb http://ftp.osuosl.org/pub/mariadb/repo/10.0/ubuntu precise main' ;
    sudo apt-get update
    sudo DEBIAN_FRONTEND=noninteractive apt-get -q --yes --force-yes -f --option DPkg::Options::=--force-confnew install mariadb-server
    sudo apt-get install libmariadbd-dev
  elif [[ $DATABASE_ADAPTER =~ mysql-(5\.[67]|8\.0) ]]; then
    cat <<EOC | sudo debconf-set-selections
mysql-apt-config mysql-apt-config/select-server select $DATABASE_ADAPTER
mysql-apt-config mysql-apt-config/repo-distro   select  ubuntu
EOC
    wget https://dev.mysql.com/get/mysql-apt-config_0.8.10-1_all.deb
    sudo dpkg --install mysql-apt-config_0.8.10-1_all.deb
    sudo apt-get update -q
    sudo apt-get install -q -y -o Dpkg::Options::=--force-confnew mysql-server
  else
    # 5.5
    sudo apt-get update -q
    sudo rm -rf /var/lib/mysql/ # for downgrade
    sudo DEBIAN_FRONTEND=noninteractive apt-get -q --yes --force-yes -f --option DPkg::Options::=--force-confnew install mysql-server-5.5 mysql-client-5.5 mysql-server-core-5.5
  fi
  sudo mysql_upgrade
  sudo service mysql start
fi
