#!/bin/sh
rsync -Irp --exclude ".git" --progress . ap116:isucon/webapp/perl/
rsync -Irp --exclude ".git" --progress . ap216:isucon/webapp/perl/
ssh -t ap116 sudo /etc/init.d/supervisord restart
ssh -t ap216 sudo /etc/init.d/supervisord restart

