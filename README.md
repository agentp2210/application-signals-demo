# Introduction
This is a modified version of the [spring-petclinic-microservices](https://github.com/spring-petclinic/spring-petclinic-microservices) Spring Boot sample application. 
Our modifications focus on showcasing the capabilities of Application Signals within a Spring Boot environment.
If your interest lies in exploring the broader aspects of the Spring Boot stack, we recommend visiting the original repository at [spring-petclinic-microservices](https://github.com/spring-petclinic/spring-petclinic-microservices).

In the following, we will focus on how customers can set up the current sample application to explore the features of Application Signals.

# Disclaimer

This code for sample application is intended for demonstration purposes only. It should not be used in a production environment or in any setting where reliability/security is a concern.

# Prerequisite
* A Linux or Mac machine with x86-64 (AMD64) architecture is required for building Docker images for the sample application.
* Docker is installed and running on the machine.
* AWS CLI 2.x is installed. For more information about installing the AWS CLI, see [Install or update the latest version of the AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html).
* kubectl is installed - https://docs.aws.amazon.com/eks/latest/userguide/install-kubectl.html
* eksctl is installed - https://docs.aws.amazon.com/eks/latest/userguide/eksctl.html
* jq is installed - https://jqlang.github.io/jq/download/
* [Optional] If you plan to install the infrastructure resources using Terraform, terraform cli is required. https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli

# EKS demo

## Deploy via Shell Scripts

### Build the sample application images and push to ECR

1. Build container images for each micro-service application

``` shell

./mvnw clean install -P buildDocker
```

2. Create an ECR repo for each micro service and push the images to the relevant repos. Replace the aws account id and the AWS Region.

``` shell
export ACCOUNT=`aws sts get-caller-identity | jq .Account -r`
export REGION='us-east-1'
./push-ecr.sh
```

### Try Application Signals with the sample application

1. Create an EKS cluster, enable Application Signals, and deploy the sample application to your EKS cluster. Replace `new-cluster-name` with the name that you want to use for the new cluster. Replace `region-name` with the same region in previous section "**Build the sample application images and push to ECR**".

``` shell
cd scripts/eks/appsignals/one-step && ./setup.sh new-cluster-name region-name
```

2. Clean up all the resources. Replace `new-cluster-name` and `region-name` with the same values that you use in previous step.

``` shell
cd scripts/eks/appsignals/one-step && ./cleanup.sh new-cluster-name region-name
```

Please be aware that this sample application includes a publicly accessible Application Load Balancer (ALB), enabling easy interaction with the application. If you perceive this public ALB as a security risk, consider restricting access by employing [security groups](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-update-security-groups.html).

## Deploy via Terraform

1. Go to the terraform directory under the project. Prepare Terraform S3 backend and set required environment variables

   ``` shell
   cd terraform/eks

   aws s3 mb s3://tfstate-$(uuidgen | tr A-Z a-z)

   export AWS_REGION=us-east-1
   export TFSTATE_KEY=application-signals/demo-applications
   export TFSTATE_BUCKET=$(aws s3 ls --output text | awk '{print $3}' | grep tfstate-)
   export TFSTATE_REGION=$AWS_REGION
   ```

2. Deploy EKS cluster and RDS postgreSQL database.

   ``` shell

   export TF_VAR_cluster_name=app-signals-demo
   export TF_VAR_cloudwatch_observability_addon_version=v1.5.1-eksbuild.1

   terraform init -backend-config="bucket=${TFSTATE_BUCKET}" -backend-config="key=${TFSTATE_KEY}" -backend-config="region=${TFSTATE_REGION}"

   terraform apply --auto-approve
   ```

   The deployment takes 20 - 25 minutes.

3. Build and push docker images

   ``` shell
   cd ../.. 

   ./mvnw clean install -P buildDocker

   export ACCOUNT=`aws sts get-caller-identity | jq .Account -r`
   export REGION=$AWS_REGION

   ./push-ecr.sh
   ```

4. Deploy Kubernetes resources

   Change the cluster-name, alias and region if you configure them differently.

   ``` shell
   cd terraform/eks
   TF_VAR_cluster_name=$(terraform output -raw cluster_name)
   AWS_REGION=us-east-1

   aws eks update-kubeconfig --name $TF_VAR_cluster_name  --kubeconfig ~/.kube/config --region $AWS_REGION --alias $TF_VAR_cluster_name
   ./scripts/eks/appsignals/tf-deploy-k8s-res.sh

   ```

5. Create Canaries and SLOs

   ``` shell
   endpoint=$(kubectl get ingress -o json  --output jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}')
   cd scripts/eks/appsignals/
   ./create-canaries.sh $AWS_REGION create $endpoint
   ./create-slo.sh $TF_VAR_cluster_name $AWS_REGION
   ```

6. Visit Application

   ``` shell
   endpoint="http://$(kubectl get ingress -o json  --output jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}')"

   echo "Visit the following URL to see the sample app running: $endpoint"
   ```

7. Cleanup

   Delete ALB ingress, SLOs and Canaries before destroy terraform stack.

   ``` shell

   kubectl delete -f ./scripts/eks/appsignals/sample-app/alb-ingress/petclinic-ingress.yaml

   ./cleanup-slo.sh $REGION

   ./create-canaries.sh $REGION delete

   cd ../../../terraform/eks
   terraform destroy --auto-approve
   ```

# EC2 Demo
The following instructions describe how to set up the pet clinic sample application on EC2 instances. You can run these steps in your personal AWS account to follow along.

1. Create resources and deploy sample app. Replace `region-name` with the region you choose.
   ```
   cd scripts/ec2/appsignals/ && ./setup-ec2-demo.sh --region=region-name
   ```


2. Clean up after you are done with the sample app. Replace `region-name` with the same value that you use in previous step.
   ```
   cd scripts/ec2/appsignals/ && ./setup-ec2-demo.sh --operation=delete --region=region-name
   ```


# K8s Demo
The following instructions describe how to set up the pet clinic sample application on [minikube](https://minikube.sigs.k8s.io/docs/) in an EC2 instance. You can run these steps in your personal AWS account to follow along. Note that you need to first [build and push the sample app images as described for EKS Demo](###Build-the-sample-application-images-and-push-to-ECR).

1. Launching an EC2 instance with the following configurations:
   * Amazon Linux 2023
   * t2.2xlarge instance type
   * Default VPC
   * Enable public IPv4 address
   * A security group that accepts all incoming traffic
   * Configure 30 GB of storage
   * An EC2 IAM instance profile with the following managed policies:
      * AmazonEC2FullAccess
      * AmazonDynamoDBFullAccess
      * AmazonKinesisFullAccess
      * AmazonS3FullAccess
      * AmazonSQSFullAccess
      * AWSXrayWriteOnlyAccess
      * CloudWatchAgentServerPolicy
   * Set the metadata response hop limit to 3 or higher

2. Set up Minikube Cluster and Helm
   ```
   sudo yum install docker -y && \
   sudo service docker start && \
   sudo usermod -aG docker $USER && newgrp docker

   curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64 && \
   sudo install minikube-linux-amd64 /usr/local/bin/minikube && \
   minikube start --driver docker --cpus 8 --memory 20000 && \
   alias kubectl="minikube kubectl --" 

   kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.12.0/cert-manager.yaml

   curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 && \
   chmod 700 get_helm.sh && \
   ./get_helm.sh 
   ```

3. Configure Minikube to access AWS ECR
   ```
   $ minikube addons configure registry-creds

   Do you want to enable AWS Elastic Container Registry? [y/n]: y
   -- Enter AWS Access Key ID: <put_access_key_here>
   -- Enter AWS Secret Access Key: <put_secret_access_key_here>
   -- (Optional) Enter AWS Session Token:
   -- Enter AWS Region: <put_aws_region_of_ECR_repo_here>
   -- Enter 12 digit AWS Account ID (Comma separated list): <account_number>
   -- (Optional) Enter ARN of AWS role to assume:

   Do you want to enable Google Container Registry? [y/n]: n

   Do you want to enable Docker Registry? [y/n]: n

   Do you want to enable Azure Container Registry? [y/n]: n
   ✅  registry-creds was successfully configured

   $ minikube addons enable registry-creds
   ```

4. Install Cloudwatch Agent operator
   - Get the helm chart for Cloudwatch Agent operator
   ```
   sudo yum install git -y && \
   git clone https://github.com/aws-observability/helm-charts -q && \
   cd helm-charts/charts/amazon-cloudwatch-observability/ 
   ```
   - Modify the default config to disable Container Insights (which sometimes cause issues in minikube cluster). Open the `values.yaml` file and remove the following part:
   ```
         "kubernetes": {
            "enhanced_container_insights": true
          },
   ```
   - Use helm chart to install Cloudwatch Agent operator. Replace `cluster-name` with the name that you want to use. Replace `region-name` with the aws region that you choose.
   ```
   export REGION=region-name
   export CLUSTER=cluster-name
   helm upgrade --install --debug --namespace amazon-cloudwatch amazon-cloudwatch-operator ./ --create-namespace --set region=${REGION} --set clusterName=${CLUSTER}
   ```

5. Deploy the sample app to the minikube cluster. Replace `region-name` with the aws region that you use in last step. 
   ```
   cd ~
   git clone https://github.com/aws-observability/application-signals-demo.git
   cd application-signals-demo/scripts/k8s/appsignals
   ./deploy-sample-app.sh your-region-name
   ```

6. Destroy the minikube cluster and all resources in it
   ```
   minikube delete
   ```
