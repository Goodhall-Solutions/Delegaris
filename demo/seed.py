"""Fills the simulated AWS (moto) with sample resources and registers them in Delegaris.

Run by the seed service in docker-compose.yml in this folder. Safe to run again: it does nothing
when everything is there, and when the simulated AWS has been emptied (it keeps nothing once it is
stopped) it fills it again and points the groups and Remote Desktop at the new machines.
"""

import os
import sys

import boto3
import httpx

APP_URL = os.environ.get("APP_URL", "http://localhost:8080")
ADMIN_USER = os.environ.get("ADMIN_USER", "admin")
ADMIN_PASSWORD = os.environ.get("ADMIN_PASSWORD", "admin")
REGION = "eu-west-2"
ROLE = "DelegarisRole"
ACCOUNTS = {"Production": "111111111111", "Development": "222222222222"}
# What each account manages: beyond EC2 and RDS, so the demo shows the other kinds.
SERVICES = {
    "Production": ["ec2", "rds", "asg", "ecs", "redshift"],
    "Development": ["ec2", "rds", "eks", "sagemaker"],
}


def session_for(account_id: str) -> boto3.Session:
    creds = boto3.client("sts", region_name=REGION).assume_role(
        RoleArn=f"arn:aws:iam::{account_id}:role/{ROLE}", RoleSessionName="seed"
    )["Credentials"]
    return boto3.Session(
        aws_access_key_id=creds["AccessKeyId"],
        aws_secret_access_key=creds["SecretAccessKey"],
        aws_session_token=creds["SessionToken"],
        region_name=REGION,
    )


def launch(session: boto3.Session, name: str, size: str, stopped: bool = False, **tags: str) -> None:
    ec2 = session.client("ec2")
    image = ec2.describe_images(Owners=["amazon"])["Images"][0]["ImageId"]
    tag_list = [{"Key": "Name", "Value": name}] + [{"Key": k.replace("_", ":"), "Value": v} for k, v in tags.items()]
    instance = ec2.run_instances(
        ImageId=image,
        MinCount=1,
        MaxCount=1,
        InstanceType=size,
        TagSpecifications=[{"ResourceType": "instance", "Tags": tag_list}],
    )["Instances"][0]["InstanceId"]
    if stopped:
        ec2.stop_instances(InstanceIds=[instance])


def database(session: boto3.Session, name: str, engine: str, size: str, stopped: bool = False, **tags: str) -> None:
    rds = session.client("rds")
    rds.create_db_instance(
        DBInstanceIdentifier=name,
        Engine=engine,
        DBInstanceClass=size,
        AllocatedStorage=50,
        MasterUsername="dbadmin",
        MasterUserPassword="not-a-real-password",
        Tags=[{"Key": k, "Value": v} for k, v in tags.items()],
    )
    if stopped:
        rds.stop_db_instance(DBInstanceIdentifier=name)


def auto_scaling_group(session: boto3.Session, name: str, desired: int, **tags: str) -> None:
    ec2, asg = session.client("ec2"), session.client("autoscaling")
    image = ec2.describe_images(Owners=["amazon"])["Images"][0]["ImageId"]
    asg.create_launch_configuration(LaunchConfigurationName=f"{name}-lc", ImageId=image, InstanceType="m6i.large")
    asg.create_auto_scaling_group(
        AutoScalingGroupName=name,
        LaunchConfigurationName=f"{name}-lc",
        MinSize=1,
        DesiredCapacity=desired,
        MaxSize=6,
        AvailabilityZones=[f"{REGION}a"],
        Tags=[
            {"ResourceId": name, "ResourceType": "auto-scaling-group", "Key": k, "Value": v, "PropagateAtLaunch": k == "Name"}
            for k, v in {"Name": name, **tags}.items()
        ],
    )


def ecs_service(session: boto3.Session, cluster: str, name: str, desired: int, **tags: str) -> None:
    ecs = session.client("ecs")
    ecs.create_cluster(clusterName=cluster)
    ecs.register_task_definition(family=name, containerDefinitions=[{"name": name, "image": "nginx", "memory": 512}])
    ecs.create_service(
        cluster=cluster,
        serviceName=name,
        taskDefinition=name,
        desiredCount=desired,
        launchType="FARGATE",
        tags=[{"key": k, "value": v} for k, v in tags.items()],
    )


def scheduler_table(session: boto3.Session) -> None:
    """The configuration table AWS Instance Scheduler would keep, so "Read from the scheduler" has something to read."""
    ddb = session.client("dynamodb")
    table = "instance-scheduler-ConfigTable-1DEMO2DEMO3"
    ddb.create_table(
        TableName=table,
        KeySchema=[{"AttributeName": "type", "KeyType": "HASH"}, {"AttributeName": "name", "KeyType": "RANGE"}],
        AttributeDefinitions=[{"AttributeName": "type", "AttributeType": "S"}, {"AttributeName": "name", "AttributeType": "S"}],
        BillingMode="PAY_PER_REQUEST",
    )
    items = [
        {"type": "config", "name": "scheduler", "tagname": "Schedule", "default_timezone": "Europe/London"},
        {"type": "period", "name": "office-hours", "begintime": "08:00", "endtime": "20:00", "weekdays": ["mon-fri"]},
        {"type": "period", "name": "saturday-morning", "begintime": "09:00", "endtime": "13:00", "weekdays": ["sat"]},
        {"type": "period", "name": "overnight-start", "begintime": "22:00", "weekdays": ["mon-fri"]},
        {"type": "period", "name": "overnight-end", "endtime": "06:00", "weekdays": ["tue-sat"]},
        {"type": "period", "name": "weekend", "begintime": "07:00", "endtime": "19:00", "weekdays": ["sat-sun"]},
        {"type": "schedule", "name": "8-8", "description": "UK office hours", "periods": ["office-hours", "saturday-morning"], "timezone": "Europe/London"},
        {"type": "schedule", "name": "us-8-8", "description": "US office hours", "periods": ["office-hours"], "timezone": "America/New_York"},
        {"type": "schedule", "name": "24x7", "description": "Always on", "override_status": "running"},
        {"type": "schedule", "name": "22-06", "description": "Overnight batch", "periods": ["overnight-start", "overnight-end"], "timezone": "Europe/London"},
        {"type": "schedule", "name": "weekend-batch", "description": "Weekend processing", "periods": ["weekend"]},
    ]
    for item in items:
        ddb.put_item(TableName=table, Item={k: ({"SS": v} if isinstance(v, list) else {"S": v}) for k, v in item.items()})


def seed_aws() -> None:
    prod = session_for(ACCOUNTS["Production"])
    launch(prod, "web-1", "m6i.large", Team="web", Environment="prod", Schedule="24x7")
    launch(prod, "web-2", "m6i.large", Team="web", Environment="prod", Schedule="24x7")
    launch(prod, "reporting-batch", "c6i.2xlarge", stopped=True, Team="data", Environment="prod", Schedule="22-06")
    launch(prod, "bastion", "t3.micro", Team="platform", Delegaris="protected", Environment="prod")
    launch(prod, "us-support-api", "m6i.large", Team="web", Environment="prod", Schedule="us-8-8")
    auto_scaling_group(prod, "api-asg", 2, Team="web", Environment="prod", Schedule="8-8")
    ecs_service(prod, "apps", "checkout", 3, Team="web", Environment="prod", Schedule="8-8")
    prod.client("redshift").create_cluster(
        ClusterIdentifier="warehouse",
        NodeType="ra3.xlplus",
        NumberOfNodes=2,
        ClusterType="multi-node",
        MasterUsername="dbadmin",
        MasterUserPassword="NotARealPassw0rd",
        Tags=[{"Key": "Team", "Value": "data"}, {"Key": "Environment", "Value": "prod"}, {"Key": "Schedule", "Value": "8-8"}],
    )
    database(prod, "orders-db", "postgres", "db.m6g.large", Team="web", Environment="prod", Schedule="24x7")
    rds = prod.client("rds")
    rds.create_db_cluster(
        DBClusterIdentifier="analytics",
        Engine="aurora-postgresql",
        MasterUsername="dbadmin",
        MasterUserPassword="not-a-real-password",
        Tags=[{"Key": "Team", "Value": "data"}, {"Key": "Schedule", "Value": "8-8"}],
    )
    for index in (1, 2):
        rds.create_db_instance(
            DBInstanceIdentifier=f"analytics-{index}",
            DBClusterIdentifier="analytics",
            Engine="aurora-postgresql",
            DBInstanceClass="db.r6g.large",
        )

    scheduler_table(prod)

    dev = session_for(ACCOUNTS["Development"])
    launch(dev, "dev-web", "t3.medium", Team="web", Environment="dev", Schedule="8-8")
    launch(dev, "win-tools", "t3.large", Team="web", Environment="dev", Schedule="8-8")
    launch(dev, "dev-api", "t3.medium", Team="web", Environment="dev", Schedule="8-8")
    launch(dev, "qa-runner", "t3.large", stopped=True, Team="qa", Environment="dev", Schedule="8-8")
    launch(dev, "data-sandbox", "r6i.xlarge", stopped=True, Team="data", Environment="dev")
    database(dev, "dev-orders-db", "postgres", "db.t4g.medium", Team="web", Environment="dev", Schedule="8-8")
    database(dev, "qa-mysql", "mysql", "db.t4g.small", stopped=True, Team="qa", Environment="dev", Schedule="8-8")
    eks = dev.client("eks")
    eks.create_cluster(name="dev-k8s", roleArn=f"arn:aws:iam::{ACCOUNTS['Development']}:role/eks", resourcesVpcConfig={"subnetIds": ["subnet-dev"]})
    eks.create_nodegroup(
        clusterName="dev-k8s",
        nodegroupName="dev-workers",
        nodeRole=f"arn:aws:iam::{ACCOUNTS['Development']}:role/eks-node",
        subnets=["subnet-dev"],
        instanceTypes=["t3.large"],
        scalingConfig={"minSize": 1, "maxSize": 4, "desiredSize": 2},
        tags={"Team": "web", "Environment": "dev", "Schedule": "8-8"},
    )
    dev.client("sagemaker").create_notebook_instance(
        NotebookInstanceName="data-notebook",
        InstanceType="ml.t3.medium",
        RoleArn=f"arn:aws:iam::{ACCOUNTS['Development']}:role/sagemaker",
        Tags=[{"Key": "Team", "Value": "data"}, {"Key": "Environment", "Value": "dev"}],
    )


def main() -> None:
    with httpx.Client(base_url=APP_URL, timeout=30) as app:
        app.post("/api/auth/login", json={"username": ADMIN_USER, "password": ADMIN_PASSWORD}).raise_for_status()
        headers = {"X-CSRF-Token": app.get("/api/me").json()["csrf_token"]}

        fresh = not app.get("/api/admin/accounts").json()["accounts"]
        aws_empty = not session_for(ACCOUNTS["Production"]).client("ec2").describe_instances()["Reservations"]
        if not fresh and not aws_empty:
            print("Already seeded; nothing to do.")
            return
        if aws_empty:
            seed_aws()
        if fresh:
            configure(app, headers)
        else:
            print("The simulated AWS was empty (it keeps nothing once stopped), so it has been filled again.")
        link_resources(app, headers)


def configure(app: httpx.Client, headers: dict) -> None:
    """Accounts, access rules, friendly names and the sign-in page: once, on a new install."""
    for name, account_id in ACCOUNTS.items():
        app.post(
            "/api/admin/accounts",
            headers=headers,
            json={
                "name": name,
                "account_id": account_id,
                "role_arn": f"arn:aws:iam::{account_id}:role/{ROLE}",
                "regions": [REGION],
                "services": SERVICES[name],
            },
        ).raise_for_status()

    # Nobody here is given the right to edit tags. Keeping a machine on past its schedule
    # is its own permission, and the service handles the schedule tag itself.
    rules = [
        {
            "name": "Web team, their development machines",
            "principal_type": "group",
            "principal": "AWS-Web-Team",
            "actions": ["start", "stop", "keep_on", "connect"],
            "account_ids": [ACCOUNTS["Development"]],
            "tag_filters": [{"key": "Team", "value": "web"}],
        },
        {
            # Production is the delicate part: the same people may ask, but an ops lead decides.
            "name": "Web team, production, with an ops lead's approval",
            "principal_type": "group",
            "principal": "AWS-Web-Team",
            "actions": ["start", "stop", "keep_on"],
            "account_ids": [ACCOUNTS["Production"]],
            "tag_filters": [{"key": "Team", "value": "web"}],
            "needs_approval": True,
            "approvers": [{"type": "group", "principal": "AWS-Ops-Leads"}],
        },
        {
            "name": "Ops leads, anything on a schedule",
            "principal_type": "group",
            "principal": "AWS-Ops-Leads",
            "actions": ["start", "stop", "keep_on"],
            "tag_filters": [{"key": "Schedule", "value": "*"}],
        },
        {
            "name": "QA, development account only",
            "principal_type": "group",
            "principal": "AWS-QA",
            "actions": ["start", "stop", "keep_on"],
            "account_ids": [ACCOUNTS["Development"]],
            "tag_filters": [{"key": "Team", "value": "qa"}],
        },
        {
            "name": "Service desk can keep anything scheduled on",
            "principal_type": "group",
            "principal": "Service-Desk",
            "actions": ["keep_on"],
            "tag_filters": [{"key": "Schedule", "value": "*"}],
        },
    ]
    for rule in rules:
        app.post("/api/admin/rules", headers=headers, json=rule).raise_for_status()

    # The scheduler's own codes, the names people see instead, and the hours each one means.
    weekdays = [0, 1, 2, 3, 4]
    office = {"days": weekdays, "start": "08:00", "stop": "20:00"}
    names = [
        # Two office-hours schedules: the same times on different clocks. (The scheduler's own
        # table, seeded above, also gives 8-8 a Saturday morning, so "Read from the scheduler"
        # has a difference to show.)
        ("Schedule", "8-8", "UK office hours", None, {"periods": [office], "tz": "Europe/London"}),
        ("Schedule", "us-8-8", "US office hours", None, {"periods": [office], "tz": "America/New_York"}),
        ("Schedule", "24x7", "Always on", None, {"always": True}),
        ("Schedule", "22-06", "Overnight", "For batch work", {"periods": [{"days": weekdays, "start": "22:00", "stop": "06:00"}], "tz": "Europe/London"}),
        ("Environment", "prod", "Production", None, None),
        ("Environment", "dev", "Development", None, None),
    ]
    for tag_key, tag_value, label, description, hours in names:
        app.post(
            "/api/admin/labels",
            headers=headers,
            json={"tag_key": tag_key, "tag_value": tag_value, "label": label, "description": description, "hours": hours},
        ).raise_for_status()

    # Say on the sign-in page which accounts this demo has.
    app.put(
        "/api/admin/branding",
        headers=headers,
        json={
            "name": "Delegaris",
            "tagline": "Cloud infrastructure access, without cloud console access.",
            "login_note": "Demo sign-ins: admin / admin (administrator), dev / dev (developer), lead / lead (approves what dev asks for in production).",
        },
    ).raise_for_status()

    print(f"Seeded {len(ACCOUNTS)} accounts, {len(rules)} access rules and {len(names)} friendly names.")


def link_resources(app: httpx.Client, headers: dict) -> None:
    """Server groups and Remote Desktop, which name machines by their IDs: made again whenever the
    simulated AWS is filled, because its machines get new IDs each time."""
    existing = {g["name"]: g["id"] for g in app.get("/api/admin/groups").json()["groups"]}
    # Groups: the database first, then the servers that need it.
    found = {r["name"]: r for r in app.get("/api/resources?refresh=true").json()["resources"]}
    ref = lambda name: {k: found[name][k] for k in ("account_id", "region", "type", "id")}  # noqa: E731
    groups = [
        ("Development stack", "Orders database and the two dev servers", [["dev-orders-db"], ["dev-api", "dev-web"]]),
        ("Reporting", "Analytics cluster, then the batch server", [["analytics"], ["reporting-batch"]]),
    ]
    for name, description, steps in groups:
        body = {"name": name, "description": description, "steps": [[ref(member) for member in step] for step in steps]}
        if name in existing:
            app.put(f"/api/admin/groups/{existing[name]}", headers=headers, json=body).raise_for_status()
        else:
            app.post("/api/admin/groups", headers=headers, json=body).raise_for_status()

    # Remote Desktop to the Windows tools box, signed in as the person's own domain account.
    app.put(
        "/api/admin/remote",
        headers=headers,
        json={"resources": [ref("win-tools")], "address_source": "private_ip", "gateway": "rdg.corp.example",
              "username_mode": "own", "domain": "CORP"},
    ).raise_for_status()
    print(f"Set up {len(groups)} server groups and Remote Desktop.")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # make failures obvious in `docker compose up` output
        print(f"Seeding failed: {exc}", file=sys.stderr)
        raise
