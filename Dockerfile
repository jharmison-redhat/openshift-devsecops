FROM registry.access.redhat.com/ubi8/ubi

ENV AWS_ACCESS_KEY_ID ""
ENV AWS_SECRET_ACCESS_KEY ""

RUN dnf -y --setopt=tsflags=nodocs update && \
    dnf -y --setopt=tsflags=nodocs install python3 python3-pip gnupg2 httpd-tools git openssh-clients && \
    dnf -y clean all --enablerepo='*'
RUN curl http://mirror.openshift.com/pub/openshift-v4/clients/oc/latest/linux/oc.tar.gz -o /root/oc.tar.gz && \
    tar xvzf /root/oc.tar.gz -C /usr/local/bin
RUN pip3 install --upgrade --no-cache-dir ansible openshift jmespath git+https://github.com/jharmison-redhat/devsecops-api-script.git

RUN mkdir -p /app

COPY ansible.cfg /app/ansible.cfg
COPY inventory /app/inventory
COPY library /app/library
COPY roles /app/roles
COPY playbooks /app/playbooks

# You should bind-mount your own tmp and vars dirs for playbook persistence.

WORKDIR /app
ENTRYPOINT ["ansible-playbook"]
CMD ["--help"]
