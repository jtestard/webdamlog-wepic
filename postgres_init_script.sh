#!/bin/bash

# Database administrative login by Unix domain socket
#local   all             postgres                                trust
# "local" is for Unix domain socket connections only
#local   all             all                                     trust


# Create the postgres user wepic with right to create new databases along with the wepic database that may be useless if another is specified in database.yml
sudo -u postgres createuser -d -R -S wepic
sudo -u postgres createdb -O wepic wp_manager