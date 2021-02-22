import datetime
import boto3
import sys
import time

def usage():
        print("Usage : " + sys.argv[0] + " [Instance-ID] [AWS_REGION]")
        exit(1)

print len(sys.argv)
if len(sys.argv) != 3:
        usage()


try:
        ec2=boto3.resource('ec2',region_name=sys.argv[2])
        print("Identifying instance...")
        instance = ec2.Instance(sys.argv[1])
        hostname=sys.argv[1]
        for t in instance.tags:
                if t["Key"] == "Name":
                        hostname = t["Value"]
                        break

        print("Beginning AMI Backup for " + hostname)
        retention_days=5
        ami_image = instance.create_image(Name=hostname + "_AMI_Before_Patching_" + time.strftime("%d-%m-%Y-%H-%M"), NoReboot=True)
        delete_date = datetime.date.today() + datetime.timedelta(days=retention_days)
        delete_fmt = delete_date.strftime('%Y-%m-%d')
        ami_image.create_tags(Tags=[
                {
                        "Key": "Name",
                        "Value": hostname + "_AMI_" + time.strftime("%d-%m-%Y-%H-%M"),
                        "Key": "DeleteOn",
                        "Value": delete_fmt
                }
        ])

        print("Waiting for AMI Backup to complete..." + str(ami_image.image_id))

        state = "pending"

        while str(state) == 'pending' :
                try:
                        state=ec2.Image(str(ami_image.image_id)).state
                        print("Current state for AMI ID " + str(ami_image.image_id) + " is " + str(state))
                        time.sleep(30)
                except Exception as amie:
                        print("Retrying state...after 30 seconds..")
                        time.sleep(30)

#       while str(state) != "available" :
#               try:
#                       ami_image.wait_until_exists(Filters=[{'Name': 'state', 'Values': ['available']}])
#                       print("AMI Backup complete..." + str(ami_image.state))
#               except Exception as amie:
#                       print("Retrying state...")
#
#               state=ec2.Image(str(ami_image.image_id)).state
        if state == "available" :
                print("AMI Backup complete..." + str(ami_image.state))
                exit(0)
        else :
                print("AMI Backup failed...")
                exit(1)

except Exception as e:

        print(e)
        exit(1)
