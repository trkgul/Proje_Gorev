#!/bin/bash
THRESHOLD=1
EMAIL=trkgul83@gmail.com
#PART=yourdiskpart
PART=/dev/xvda1
USE=`df -h |grep $PART | awk '{ print $5 }' | cut -d'%' -f1`
if [ $USE -gt $THRESHOLD ]; then
  echo "Percent Used: $USE" | mail -s "Disk Usage Rate " -r trkgul83@gmail.com $EMAIL
fi

#/home/ec2-user