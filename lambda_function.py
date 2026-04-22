import boto3
import json
import os

def handler(event, context):
    ec2 = boto3.client(
        'ec2',
        region_name='us-east-1',
        endpoint_url=os.environ.get('LOCALSTACK_ENDPOINT', 'http://172.17.0.1:4566'),
        aws_access_key_id='255tyAzuXP5Tm8',
        aws_secret_access_key='bdWF726h3e9EgR'
    )

    instance_id = event.get('queryStringParameters', {}).get('instance_id', os.environ.get('INSTANCE_ID'))
    action = event.get('queryStringParameters', {}).get('action', 'status')

    if action == 'start':
        ec2.start_instances(InstanceIds=[instance_id])
        message = f"Instance {instance_id} démarrée."
    elif action == 'stop':
        ec2.stop_instances(InstanceIds=[instance_id])
        message = f"Instance {instance_id} arrêtée."
    else:
        response = ec2.describe_instances(InstanceIds=[instance_id])
        state = response['Reservations'][0]['Instances'][0]['State']['Name']
        message = f"Instance {instance_id} est en état : {state}"

    return {
        'statusCode': 200,
        'body': json.dumps({'message': message})
    }
