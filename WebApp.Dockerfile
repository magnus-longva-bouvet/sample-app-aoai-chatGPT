# Build the frontend
FROM node:20-alpine AS frontend  
RUN mkdir -p /home/node/app/node_modules && chown -R node:node /home/node/app

WORKDIR /home/node/app 
COPY ./frontend/package*.json ./  
USER node
RUN npm ci  
COPY --chown=node:node ./frontend/ ./frontend  
COPY --chown=node:node ./static/ ./static  
WORKDIR /home/node/app/frontend
RUN npm run build

# Build the application image
FROM python:3.11-alpine 
# Install dependencies for building Python packages and SSH
RUN apk add --no-cache --virtual .build-deps \
    build-base \
    libffi-dev \
    openssl-dev \
    curl \
    openssh \
    && apk add --no-cache \
    libpq \
    && pip install --no-cache-dir uwsgi \
    && echo "root:Docker!" | chpasswd 

# Configure SSH
RUN mkdir -p /var/run/sshd \
    && ssh-keygen -A \
    && echo "Port 2222" > /etc/ssh/sshd_config \
    && echo "ListenAddress 0.0.0.0" >> /etc/ssh/sshd_config \
    && echo "LoginGraceTime 180" >> /etc/ssh/sshd_config \
    && echo "X11Forwarding yes" >> /etc/ssh/sshd_config \
    && echo "Ciphers aes128-cbc,3des-cbc,aes256-cbc" >> /etc/ssh/sshd_config \
    && echo "MACs hmac-sha1,hmac-md5" >> /etc/ssh/sshd_config \
    && echo "StrictModes yes" >> /etc/ssh/sshd_config \
    && echo "SyslogFacility DAEMON" >> /etc/ssh/sshd_config \
    && echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config \
    && echo "PermitRootLogin yes" >> /etc/ssh/sshd_config \
    && echo "Subsystem sftp internal-sftp" >> /etc/ssh/sshd_config
EXPOSE 2222

# Copy the frontend build
COPY --from=frontend /home/node/app/static /usr/src/app/static/

# Install Python dependencies
COPY requirements.txt /usr/src/app/
RUN pip install --no-cache-dir -r /usr/src/app/requirements.txt \
    && rm -rf /root/.cache

# Copy the application files
COPY . /usr/src/app/
WORKDIR /usr/src/app  
EXPOSE 80  

# Start SSH and the application
CMD ["/bin/sh", "-c", "/usr/sbin/sshd && uwsgi --http :80 --wsgi-file app.py --callable app -b 32768"]
