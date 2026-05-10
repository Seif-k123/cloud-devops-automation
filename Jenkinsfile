pipeline {
    agent any

    environment {
        AWS_ACCESS_KEY_ID     = credentials('aws-access-key')
        AWS_SECRET_ACCESS_KEY = credentials('aws-secret-key')
        AWS_DEFAULT_REGION    = 'us-east-1'
        TF_DIR                = "${WORKSPACE}"
        ANSIBLE_DIR           = "${WORKSPACE}/ansible"
    }

    stages {

        stage('Checkout') {
            steps {
                git branch: 'main',
                    url: 'git@github.com:Seif-k123/cloud-devops-automation.git',
                    credentialsId: 'github-ssh'
            }
        }

        stage('Terraform Init') {
            steps {
                dir("${TF_DIR}") {
                    sh 'terraform init'
                }
            }
        }

        stage('Terraform Apply') {
            steps {
                dir("${TF_DIR}") {
                    sh 'terraform apply -auto-approve -var-file=/home/seifkhaled/cloud-devops-automation/terraform.tfvars'
                }
            }
        }

        stage('Wait for Servers') {
            steps {
                sleep(time: 30, unit: 'SECONDS')
            }
        }

        stage('Ansible Deploy') {
            steps {
                dir("${ANSIBLE_DIR}") {
                    sh '''
                        ansible-playbook -i inventory.ini nginx.yml \
                            --private-key /home/seifkhaled/cloud-devops-automation/ansible/my-keypair.pem
                    '''
                }
            }
        }

    }

    post {
        success {
            echo 'Infrastructure is ready and Nginx is deployed successfully.'
        }
        failure {
            echo 'Pipeline failed. Check the logs.'
        }
    }
}
