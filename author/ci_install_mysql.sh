#!/bin/bash
set -ex

if [[ $DATABASE_ADAPTER =~ (mariadb|mysql-(5\.[67]|8\.0)) ]]; then
  sudo service mysql stop
  sudo apt-get install software-properties-common
  sudo apt-key adv --recv-keys --keyserver keyserver.ubuntu.com B7B3B788A8D3785C
  if [[ $DATABASE_ADAPTER =~ mariadb ]]; then
    # https://mariadb.com/kb/en/mariadb-package-repository-setup-and-usage/
    curl -LsS https://r.mariadb.com/downloads/mariadb_repo_setup | sudo bash
    sudo apt-get update
    sudo DEBIAN_FRONTEND=noninteractive apt-get -q --yes --force-yes -f --option DPkg::Options::=--force-confnew install mariadb-server
    sudo apt-get install libmariadb-dev
    sudo mariadb-upgrade
  elif [[ $DATABASE_ADAPTER =~ mysql-(5\.[67]|8\.0) ]]; then
    cat <<EOC | sudo debconf-set-selections
mysql-apt-config mysql-apt-config/select-server select $DATABASE_ADAPTER
mysql-apt-config mysql-apt-config/repo-distro   select  ubuntu
EOC
    wget https://dev.mysql.com/get/mysql-apt-config_0.8.29-1_all.deb
    sudo dpkg --install mysql-apt-config_0.8.29-1_all.deb
    sudo apt-get update -q
    sudo apt-get install -q -y -o Dpkg::Options::=--force-confnew mysql-server
    sudo mysql_upgrade
  fi
fi
