FROM nginx:alpine
# Xóa file mặc định và không copy file mới vào
RUN rm /usr/share/nginx/html/index.html
EXPOSE 80