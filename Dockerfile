FROM nginx:alpine
RUN echo "<h1>Hello từ Kubernetes CI/CD Pipeline!</h1>" > /usr/share/nginx/html/index.html
EXPOSE 80