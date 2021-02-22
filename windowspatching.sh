#!/bin/bash
tags1=Patching
tags2=True
aws ec2 describe-instances --filter Name=tag:${tags1},Values=${tags2} --query 'Reservations[*].Instances[*].{Instance:InstanceId,InstanceIP:PrivateIpAddress,Name:Tags[?Key==`Name`]|[0].Value}' --output text --region us-east-1 > instance_info
cat instance_info | awk '{print $2}' > server.txt
cat instance_info | awk '{print $1}' > instanceid
function scan_patch
{
        > pre_patching_report
        for pre_check in `cat instanceid`
        do
 #       command_id=$(aws ssm send-command --document-name "AWS-ApplyPatchBaseline" --document-version "1" --targets '[{"Key":"tag:'${tags1}'","Values":["'${tags2}'"]}]' --parameters '{"Operation":["Scan"],"SnapshotId":[""]}' --timeout-seconds 600 --max-concurrency "50" --max-errors "0" --region us-east-1 | awk '{print $2}' | head -1 )
#        command_id=$(aws ssm send-command --document-name "AWS-ApplyPatchBaseline" --document-version "1" --targets '[{"Key":"InstanceIds","Values":["'${pre_check}'"]}]' --parameters '{"Operation":["Scan"],"SnapshotId":[""]}' --timeout-seconds 600 --max-concurrency "50" --max-errors "0" --region us-east-1 | awk '{print $2}' | head -1 )
        command_id=$(aws ssm send-command --document-name "AWS-InstallWindowsUpdates" --document-version "1" --targets '[{"Key":"InstanceIds","Values":["'${pre_check}'"]}]' --parameters '{"Action":["Scan"],"AllowReboot":["False"],"IncludeKbs":[""],"ExcludeKbs":[""],"Categories":["SecurityUpdates"],"SeverityLevels":[""],"PublishedDaysOld":[""],"PublishedDateAfter":[""],"PublishedDateBefore":[""]}' --timeout-seconds 600 --max-concurrency "50" --max-errors "0" --region us-east-1 | awk '{print $2}' | head -1 )
        while true
        do
                status=$(aws ssm list-command-invocations  --command-id "$command_id" --details --output json | grep -i "Status" | head -1  | awk -F"[:,]" '{print $2}' | cut -d '"' -f2)
                sleep 15
                if [ "$status" == "Success" ]
                then
                        server_ip=$(cat instance_info| grep -i $pre_check | awk '{print $2}') >> pre_patching_report
                        echo "===========================$pre_check($server_ip)===============================" >> pre_patching_report
                        pre_KB_id=$(aws ssm list-command-invocations  --command-id  "$command_id" --details --output text | grep -i KB)
                        echo "$pre_KB_id" >> pre_patching_report
                        echo "====================================================================================" >> pre_patching_report
                        echo "Pre Scan Successfully completed for ${pre_check}"
                        break
                elif [ "$status" == "Failed" ]
                then
                        echo "Pre Scan failed for ${pre_check}"
                        exit 1


                fi
        done
        refresh_id=$(aws ssm send-command --document-name "AWS-RefreshAssociation" --document-version "1" --targets '[{"Key":"InstanceIds","Values":["'${pre_check}'"]}]' --parameters '{}' --timeout-seconds 600 --max-concurrency "50" --max-errors "0" --region us-east-1 | awk '{print $2}' | head -1)
        while true
        do
                refresh_status=$( aws ssm list-command-invocations  --command-id "$refresh_id" --details --output json | grep -i "Status" | head -1  | awk -F"[:,]" '{print $2}' | cut -d '"' -f2)
                sleep 15
                 if [ "$refresh_status" == "Success" ]
                then
                        echo "Pre AWS-RefreshAssociation completed for ${pre_check}"
                        break
                elif [ "$refresh_status" == "Failed" ]
                then
                        echo "Pre AWS-RefreshAssociation failed for ${pre_check}"
                        exit 1

                fi
        done

done
        /usr/bin/aws sns publish --topic-arn="arn:aws:sns:us-east-1:040477774568:patching_status" --message "$(cat pre_patching_report)" --subject "$SUBJECT_PREFIX - Windows Pre Patching Report -"
}
function postcheck
{
        > post_patching_report
        for post_check in `cat instanceid`
        do
                post_check_id=$(aws ssm send-command --document-name "AWS-ApplyPatchBaseline" --document-version "1" --targets '[{"Key":"InstanceIds","Values":["'${post_check}'"]}]' --parameters '{"Operation":["Scan"],"SnapshotId":[""]}' --timeout-seconds 600 --max-concurrency "50" --max-errors "0" --region us-east-1 | awk '{print $2}' | head -1 )

                while true
                do
                        post_check_status=$(aws ssm list-command-invocations  --command-id "$post_check_id" --details --output json | grep -i "Status" | head -1  | awk -F"[:,]" '{print $2}' | cut -d '"' -f2)
                        sleep 15
                        if [ "$post_check_status" == "Success" ]
                        then
                                echo "Scan Successfully completed"
                                break
                        elif [ "$post_check_status" == "Failed" ]
                        then
                                echo "Scan failed"
                                exit 1


                        fi
                done
                        post_check_refresh_id=$(aws ssm send-command --document-name "AWS-RefreshAssociation" --document-version "1" --targets '[{"Key":"InstanceIds","Values":["'${post_check}'"]}]' --parameters '{}' --timeout-seconds 600 --max-concurrency "50" --max-errors "0" --region us-east-1 | awk '{print $2}' | head -1)
                while true
                do
                        post_check_refresh_status=$( aws ssm list-command-invocations  --command-id "$post_check_refresh_id" --details --output json | grep -i "Status" | head -1  | awk -F"[:,]" '{print $2}' | cut -d '"' -f2)
                        sleep 15
                        if [ "$post_check_refresh_status" == "Success" ]
                        then
                                echo "Report completed for ${post_check}"
                                break
                        elif [ "$post_check_refresh_status" == "Failed" ]
                        then
                                echo "Report failed for ${post_check}"
                                exit 1

                        fi
                        done
                        echo "===========================$post_check===============================" >> post_patching_report
                kb_id=$(aws ssm list-inventory-entries --instance-id $post_check  --type-name "AWS:WindowsUpdate" | grep -i `date +%Y-%m` | awk ' NR!=1 { print $4}')
                echo "$kb_id" >> post_patching_report
                echo "==========================================================================" >> post_patching_report
        done
        /usr/bin/aws sns publish --topic-arn="arn:aws:sns:us-east-1:040477774568:patching_status" --message "$(cat post_patching_report)" --subject "$SUBJECT_PREFIX - Patching Status -"


}
function patchinstance
{
       python amibackup.py $1 'us-east-1'
        [ $? -ne 0 ] && echo "AMI Backup failed for instance $1" && return
        for server_line in $(cat server.txt)
        do
        nc -w 10 -vz $server_line 3389 &> /dev/null
                if [ $? -eq 0 ]
                then
                        break
                else
                        echo "$server_line is down.................."
                fi
        done
         patching_id=$(aws ssm send-command --document-name "AWS-InstallWindowsUpdates" --document-version "1" --targets '[{"Key":"InstanceIds","Values":["'$1'"]}]' --parameters '{"Action":["Install"],"AllowReboot":["True"],"IncludeKbs":[""],"ExcludeKbs":[""],"Categories":["SecurityUpdates"],"SeverityLevels":[""],"PublishedDaysOld":[""],"PublishedDateAfter":[""],"PublishedDateBefore":[""]}' --timeout-seconds 600 --max-concurrency "50" --max-errors "0" --region us-east-1 | awk '{print $2}' | head -1)
        while true
        do
                patching_status=$(aws ssm list-command-invocations  --command-id "$patching_id" --details --output json | grep -i "Status" | head -1  | awk -F"[:,]" '{print $2}' | cut -d '"' -f2)
                sleep 15
                if [ "$patching_status" == "Success" ]
                then
                        echo "Patching completed for $1"
                        break
                elif [ "$patching_status" == "Failed" ]
                then
                        echo "Patching failed for $1"
                        exit 1

                fi
        done

}

function patching
{
        for server_line in $(cat server.txt)
        do
        nc -w 10 -vz $server_line 3389 &> /dev/null
        if [ $? -eq 0 ]
        then

                instance_id=$(cat instance_info | grep -i $server_line | awk '{print $1} ')
                $(patchinstance $instance_id | tee -a $instance_id.log) &
                else
                        echo "$server_line is down.................." | tee -a $instance_id.log
                fi
        done
        data=`jobs | wc -l`
        while [ $data -ne 0 ]
        do
                data=`jobs | wc -l`
                jobs
        sleep 10
        done
}
echo "Enter the operation which you want to execute on server: "
echo "=================1. Pre Check================"
echo "=================2. Patching================="
echo "=================3. Post Check==============="
read -p "Enter the option from above menu: " op
case $op in
        1)
           echo "You have selected Pre Check Option: "
           read -p "Press 'y' to continue......:  " res
           if [ $res == "y" ]
           then
                echo "Begining Patch Scan Checks........."
                scan_patch
                echo "Ending Patch Scan Checks........."
           else
                echo "You are not selected 'y' option...Please rerun script again and select 'y' option to continue...."
           fi
           ;;
        2) echo "You have selected Patching Option: "
           read -p "Press 'y' to continue......:  " res
           if [ $res == "y" ]
           then
                echo "Begining Patching........."
                patching
                echo "Ending Patching......"
           else
                echo "You are not selected 'y' option...Please rerun script again and select 'y' option to continue...."

           fi
           ;;
        3) echo "You have selected Post Check Option: "
           read -p "Press 'y' to continue......:  " res
           if [ $res == "y" ]
           then
                echo "Begining Post Checks........."
                postcheck
                echo "Ending Post Checks........."
           else
                echo "You are not selected 'y' option...Please rerun script again and select 'y' option to continue...."
           fi

           ;;
        *) echo "Invalid Option !!!!!" ;;
esac

