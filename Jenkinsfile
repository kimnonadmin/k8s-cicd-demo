pipeline {
    agent any

    environment {
        AWS_REGION        = 'ap-southeast-1'
        AWS_ACCOUNT_ID    = '475309741409'
        ECR_REPOSITORY    = 'kim-k8s-cicd-app'
        ECR_REGISTRY      = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

        IMAGE_TAG         = "v${BUILD_NUMBER}"
        IMAGE_URI         = "${ECR_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}"

        K8S_NAMESPACE     = 'cicd-lab'
        CONTROL_PUBLIC_IP = '13.212.196.141'
    }

    stages {
        stage('1. Checkout') {
            steps {
                checkout scm
            }
        }

        stage('2. Build Image') {
            steps {
                // Nếu Dockerfile nằm ngay ngoài thư mục gốc repo thì giữ nguyên '.', nếu nằm trong folder 'app' thì dùng dir('app')
                sh '''
                    set -eu
                    docker build -t "$IMAGE_URI" .
                '''
            }
        }

        stage('3. Smoke Test') {
            steps {
                sh '''
                    set -eu
                    TEST_CONTAINER="myapp-test-${BUILD_NUMBER}"

                    docker run -d --name "$TEST_CONTAINER" "$IMAGE_URI"
                    sleep 3
                    docker exec "$TEST_CONTAINER" wget -q -O /dev/null http://127.0.0.1/ || docker exec "$TEST_CONTAINER" curl -s http://127.0.0.1/
                    docker rm -f "$TEST_CONTAINER"
                '''
            }
        }

        stage('4. Push Image to ECR') {
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws-ecr-credentials']]) {
                    sh '''
                        set +x
                        set -eu

                        aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$ECR_REGISTRY"

                        set -x
                        docker push "$IMAGE_URI"
                    '''
                }
            }
        }

        stage('5. Open SSH Tunnel') {
            steps {
                sshagent(['k8s-ssh-key']) {
                    sh '''
                        set -eu
                        mkdir -p ~/.ssh
                        ssh-keyscan -H "$CONTROL_PUBLIC_IP" >> ~/.ssh/known_hosts

                        if [ -f /tmp/k8s-tunnel.pid ]; then
                            kill $(cat /tmp/k8s-tunnel.pid) || true
                            rm -f /tmp/k8s-tunnel.pid
                        fi

                        ssh -o ExitOnForwardFailure=yes -f -N -L 16443:127.0.0.1:6443 "ubuntu@${CONTROL_PUBLIC_IP}"
                        
                        # Kiểm tra port 16443 đã lắng nghe chưa (không xài nc)
                        timeout 10 bash -c 'until echo > /dev/tcp/127.0.0.1/16443; do sleep 1; done'
                    '''
                }
            }
        }

        stage('6. Refresh ECR Pull Secret') {
            steps {
                withCredentials([
                    [$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws-ecr-credentials'],
                    file(credentialsId: 'kubeconfig-hybrid-lab', variable: 'KUBECONFIG')
                ]) {
                    sh '''
                        set +x
                        set -eu

                        ECR_PASSWORD=$(aws ecr get-login-password --region "$AWS_REGION")

                        kubectl -n "$K8S_NAMESPACE" create secret docker-registry ecr-registry-secret \
                            --docker-server="$ECR_REGISTRY" \
                            --docker-username=AWS \
                            --docker-password="$ECR_PASSWORD" \
                            --dry-run=client -o yaml | kubectl apply -f -

                        unset ECR_PASSWORD
                    '''
                }
            }
        }

        stage('7. Deploy to Kubernetes') {
            steps {
                withCredentials([
                    file(credentialsId: 'kubeconfig-hybrid-lab', variable: 'KUBECONFIG')
                ]) {
                    sh '''
                        set -eu

                        sed "s|MY_ECR_IMAGE|${IMAGE_URI}|g" k8s/deployment.yaml | kubectl apply -f -
                        kubectl apply -f k8s/service.yaml
                        kubectl -n "$K8S_NAMESPACE" rollout status deployment/myapp --timeout=180s
                    '''
                }
            }
        }

        stage('8. Verify') {
            steps {
                withCredentials([
                    file(credentialsId: 'kubeconfig-hybrid-lab', variable: 'KUBECONFIG')
                ]) {
                    sh '''
                        set -eu

                        kubectl -n "$K8S_NAMESPACE" get deployment myapp
                        kubectl -n "$K8S_NAMESPACE" get pods -l app=myapp -o wide
                        kubectl -n "$K8S_NAMESPACE" get service myapp-service
                        kubectl -n "$K8S_NAMESPACE" get deployment myapp -o jsonpath='{.spec.template.spec.containers[0].image}'
                        echo
                    '''
                }
            }
        }
    }

    post {
        always {
            sh '''
                docker rm -f "myapp-test-${BUILD_NUMBER}" 2>/dev/null || true

                if [ -f /tmp/k8s-tunnel.pid ]; then
                    kill "$(cat /tmp/k8s-tunnel.pid)" 2>/dev/null || true
                    rm -f /tmp/k8s-tunnel.pid
                fi
            '''
        }
        success {
            echo 'Pipeline thành công: Image đã push lên ECR và deploy thành công lên Kubernetes!'
        }
        failure {
            echo 'Pipeline thất bại. Vui lòng kiểm tra Console Output của bước bị lỗi.'
        }
    }
}