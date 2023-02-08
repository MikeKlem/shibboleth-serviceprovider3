ARG BASE_REGISTRY=registry1.dso.mil
ARG BASE_IMAGE=ironbank/redhat/ubi/ubi8
ARG BASE_TAG=8.7

FROM ${BASE_REGISTRY}/${BASE_IMAGE}:${BASE_TAG}

# Define args and set a default value
ARG maintainer=solute
ARG imagename=shibboleth-sp
ARG version=3.2.1

MAINTAINER $maintainer
LABEL Vendor="SOLUTE"
LABEL ImageType="Base"
LABEL ImageName=$imagename
LABEL ImageOS=centos8
LABEL Version=$version

LABEL Build docker build --rm --tag $maintainer/$imagename .

RUN ln -sf /usr/share/zoneinfo/UTC /etc/localtime \
    && echo "NETWORKING=yes" > /etc/sysconfig/network

RUN rm -fr /var/cache/yum/* && yum clean all && \
    rpm --import https://dl.fedoraproject.org/pub/epel/RPM-GPG-KEY-EPEL-8 && \
    dnf -y install --setopt=tsflags=nodocs https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm &&\
    dnf -y update && \
    dnf -y install net-tools wget curl tar unzip man vim httpd python39 python39-mod_wsgi supervisor && \
    dnf clean all

#install shibboleth, cleanup httpd
RUN curl -o /etc/yum.repos.d/security:shibboleth.repo \
      http://download.opensuse.org/repositories/security://shibboleth/CentOS_8/security:shibboleth.repo \
      && dnf -y install shibboleth.x86_64 \
      && dnf clean all \
      && rm /etc/httpd/conf.d/autoindex.conf \
      && rm /etc/httpd/conf.d/userdir.conf \
      && rm /etc/httpd/conf.d/welcome.conf

# Shibboleth filesystem setup
RUN rm -f /etc/shibboleth/sp-*.pem \
    && ln -sf /secrets/shib-sp-pki/encryption-key.pem /etc/shibboleth/sp-encrypt-key.pem \
    && ln -sf /secrets/shib-sp-pki/encryption-cert.pem /etc/shibboleth/sp-encrypt-cert.pem \
    && ln -sf /secrets/shib-sp-pki/signing-key.pem /etc/shibboleth/sp-signing-key.pem \
    && ln -sf /secrets/shib-sp-pki/signing-cert.pem /etc/shibboleth/sp-signing-cert.pem \
    && mkdir /etc/shibboleth/adhoc-md
      
ADD ./httpd/shib.conf /etc/httpd/conf.d/
ADD ./shibboleth/* /etc/shibboleth/

# tweaks to httpd configuration
RUN sed -i 's/CustomLog "logs\/access_log"/CustomLog "\/dev\/stdout"/g' /etc/httpd/conf/httpd.conf \
    && sed -i 's/ErrorLog "logs\/error_log"/ErrorLog "\/dev\/stderr"/g' /etc/httpd/conf/httpd.conf \
    && sed -i '/UseCanonicalName/c\UseCanonicalName On' /etc/httpd/conf/httpd.conf
ADD httpd/server-tokens.conf /etc/httpd/conf.d/

# add a basic page to shibb's default protected directory
RUN mkdir -p /var/www/html/sso/
ADD httpd/index.html /var/www/html/sso/


# setup supervisord
ADD system/supervisord.conf /etc/supervisor/
RUN mkdir -p /etc/supervisor/conf.d
ADD system/startup.sh /usr/local/bin/
ADD system/generate_shibboleth_config.py /usr/local/bin/

# Set up the WSGI app
ADD app/requirements.txt /app/
RUN python3.9 -m venv /app/env \
    && . /app/env/bin/activate \
    && python -m pip install -U pip==21.0.1 \
    && pip install -r /app/requirements.txt
ADD app/ /app/
ADD httpd/wsgi.conf /etc/httpd/conf.d/

EXPOSE 80

CMD ["/usr/local/bin/startup.sh"]
