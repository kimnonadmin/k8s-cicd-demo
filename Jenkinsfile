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
        WORKER_PUBLIC_IP  = '18.143.90.89' // IP Worker Node để Smoke Test HTTP Endpoint
        APP_NAME          = 'myapp'
        K8S_CMD           = 'kubectl --server=https://127.0.0.1:16443 --insecure-skip-tls-verify=true'
    }

    stages {
        stage('1. Checkout') {
            steps {
                checkout scm
            }
        }

        stage('2. Build Image') {
            steps {
                sh '''
                    set -eu
                    docker build -t "$IMAGE_URI" .
                '''
            }
        }

        stage('3. Local Smoke Test') {
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
                sshagent(['k8s-control-ssh']) {
                    sh '''
                        set -eu
                        mkdir -p ~/.ssh
                        ssh-keyscan -H "$CONTROL_PUBLIC_IP" >> ~/.ssh/known_hosts

                        # Dọn dẹp tunnel cũ nếu có
                        if [ -f /tmp/k8s-tunnel.pid ]; then
                            kill $(cat /tmp/k8s-tunnel.pid) || true
                            rm -f /tmp/k8s-tunnel.pid
                        fi

                        # Forward cổng 16443 qua IP nội bộ
                        ssh -f -N \
                            -o ExitOnForwardFailure=yes \
                            -o ServerAliveInterval=10 \
                            -o ServerAliveCountMax=3 \
                            -L 127.0.0.1:16443:10.20.10.69:6443 \
                            "ubuntu@${CONTROL_PUBLIC_IP}"

                        # Chờ cổng 16443 sẵn sàng
                        timeout 15 bash -c 'until echo > /dev/tcp/127.0.0.1/16443; do sleep 1; done'
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

                        $K8S_CMD -n "$K8S_NAMESPACE" create secret docker-registry ecr-registry-secret \
                            --docker-server="$ECR_REGISTRY" \
                            --docker-username=AWS \
                            --docker-password="$ECR_PASSWORD" \
                            --dry-run=client -o yaml | $K8S_CMD -n "$K8S_NAMESPACE" apply -f -

                        unset ECR_PASSWORD
                    '''
                }
            }
        }

        stage('7. Deploy & K8s Rollout Verify') {
            steps {
                withCredentials([file(credentialsId: 'kubeconfig-hybrid-lab', variable: 'KUBECONFIG')]) {
                    sh '''
                        set -eu

                        echo "=== BƯỚC 1: APPLY MANIFESTS & ANNOTATE CAUSE ==="
                        sed "s|MY_ECR_IMAGE|${IMAGE_URI}|g" deployment.yaml | $K8S_CMD -n "$K8S_NAMESPACE" apply -f -
                        $K8S_CMD -n "$K8S_NAMESPACE" apply -f service.yaml

                        $K8S_CMD -n "$K8S_NAMESPACE" annotate deployment/"$APP_NAME" \
                          kubernetes.io/change-cause="image=${IMAGE_URI}, build=${BUILD_NUMBER}, commit=${GIT_COMMIT:-N/A}" \
                          --overwrite

                        echo "=== BƯỚC 2: KIỂM TRA ROLLOUT STATUS (TIMEOUT 180S) ==="
                        if ! $K8S_CMD -n "$K8S_NAMESPACE" rollout status deployment/"$APP_NAME" --timeout=180s; then
                            echo " K8s Rollout thất bại! Đang lấy log chẩn đoán..."

                            # 1. Capture Diagnostics trước khi pod lỗi bị xóa
                            $K8S_CMD -n "$K8S_NAMESPACE" get pods -l app="$APP_NAME" -o wide || true
                            $K8S_CMD -n "$K8S_NAMESPACE" get events -n "$K8S_NAMESPACE" --sort-by=.metadata.creationTimestamp || true
                            $K8S_CMD -n "$K8S_NAMESPACE" logs -l app="$APP_NAME" --tail=100 || true

                            echo " Tiến hành Auto-Rollback về phiên bản cũ..."
                            $K8S_CMD -n "$K8S_NAMESPACE" rollout undo deployment/"$APP_NAME"
                            $K8S_CMD -n "$K8S_NAMESPACE" rollout status deployment/"$APP_NAME" --timeout=180s || true

                            exit 1
                        fi
                    '''
                }
            }
        }

        stage('8. Post-Deploy HTTP Smoke Test') {
            steps {
                script {
                    // Retry curl 5 lần, mỗi lần cách nhau 3 giây
                    int result = sh(
                        script: """
                            curl --fail --silent --show-error --retry 5 --retry-delay 3 "http://${WORKER_PUBLIC_IP}:30080/"
                        """,
                        returnStatus: true
                    )

                    if (result != 0) {
                        withCredentials([file(credentialsId: 'kubeconfig-hybrid-lab', variable: 'KUBECONFIG')]) {
                            sh '''
                                echo " HTTP Smoke Test thất bại! Ứng dụng không phản hồi thành công qua NodePort."

                                # Capture Diagnostics
                                $K8S_CMD -n "$K8S_NAMESPACE" get pods -l app="$APP_NAME" -o wide || true
                                $K8S_CMD -n "$K8S_NAMESPACE" logs -l app="$APP_NAME" --tail=100 || true

                                echo " Tiến hành Auto-Rollback về phiên bản cũ..."
                                $K8S_CMD -n "$K8S_NAMESPACE" rollout undo deployment/"$APP_NAME"
                                $K8S_CMD -n "$K8S_NAMESPACE" rollout status deployment/"$APP_NAME" --timeout=180s || true

                                exit 1
                            '''
                        }
                    } else {
                        echo " HTTP Smoke Test thành công rực rỡ!"
                    }
                }
            }
        }
    }

    post {
        always {
            // In ra lịch sử Deployment trước khi đóng SSH Tunnel
            withCredentials([file(credentialsId: 'kubeconfig-hybrid-lab', variable: 'KUBECONFIG')]) {
                sh '''
                    echo "=== LỊCH SỬ DEPLOYMENT HIỆN TẠI ==="
                    $K8S_CMD -n "$K8S_NAMESPACE" rollout history deployment/"$APP_NAME" || true
                '''
            }

            // Dọn dẹp local container và SSH Tunnel
            sh '''
                docker rm -f "myapp-test-${BUILD_NUMBER}" 2>/dev/null || true

                if [ -f /tmp/k8s-tunnel.pid ]; then
                    kill "$(cat /tmp/k8s-tunnel.pid)" 2>/dev/null || true
                    rm -f /tmp/k8s-tunnel.pid
                fi
            '''
        }
        success {
            echo 'Pipeline thành công: Image đã push lên ECR, deploy và verify thành công lên Kubernetes!'
        }
        failure {
            echo 'Pipeline thất bại. Hệ thống đã tự động Rollback (nếu lỗi ở bước Deploy/Smoke Test). Vui lòng kiểm tra Console Output.'
        }
    }
}