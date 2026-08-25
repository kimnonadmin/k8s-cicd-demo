FROM nginx:alpine
RUN echo "<h1>Hello from Kubernetes CI/CD Pipeline version 3!</h1>" > /usr/share/nginx/html/index.html
EXPOSE 80