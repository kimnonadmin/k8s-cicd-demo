FROM nginx:alpine
# Cố tình ghi nội dung báo lỗi vào index.html 
RUN echo "<h1>This File is Broken</h1>" > /usr/share/nginx/html/wrong_path.html
EXPOSE 80