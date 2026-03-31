#! /bin/bash

sudo -E restic backup \
  /var/lib/docker/volumes \
  /home/whlapinel