#!/bin/bash
set -ex

if [[ $DATABASE_ADAPTER =~ (mariadb|mysql-(5\.7|8\.0)) ]]; then
  sudo service mysql stop
  sudo apt-get install software-properties-common
  if [[ $DATABASE_ADAPTER =~ mariadb ]]; then
    sudo apt-key adv --recv-keys --keyserver keyserver.ubuntu.com B7B3B788A8D3785C
    # https://mariadb.com/kb/en/mariadb-package-repository-setup-and-usage/
    curl -LsS https://r.mariadb.com/downloads/mariadb_repo_setup | sudo bash
    sudo apt-get update -q
    sudo apt-get install -q --yes --force-yes -f --option DPkg::Options::=--force-confnew mariadb-server libmariadb-dev
    sudo mariadb-upgrade
  elif [[ $DATABASE_ADAPTER =~ mysql-5\.7 ]]; then
    sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 467B942D3A79BD29
    cat <<EOC | sudo debconf-set-selections
mysql-apt-config mysql-apt-config/select-server select $DATABASE_ADAPTER
mysql-apt-config mysql-apt-config/repo-codename select bionic
mysql-apt-config mysql-apt-config/repo-distro   select ubuntu
EOC
    wget https://dev.mysql.com/get/mysql-apt-config_0.8.29-1_all.deb
    sudo dpkg --install mysql-apt-config_0.8.29-1_all.deb
    sudo apt-get update -q
    sudo apt-cache policy mysql-server
    sudo apt-get remove --yes mysql-client-8.0 mysql-client-core-8.0
    sudo apt-get install -q --yes -f --option DPkg::Options::=--force-confnew mysql-client=5.7* mysql-community-server=5.7* mysql-server=5.7*
  fi
fi
