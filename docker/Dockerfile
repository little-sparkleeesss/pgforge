ARG BASE=18-bookworm

FROM postgres:${BASE}

ARG VCHORD
ARG POSTGRES_UID=999
ARG POSTGRES_GID=999

# RUN sed -i 's/deb.debian.org/mirrors.ustc.edu.cn/g' /etc/apt/sources.list.d/debian.sources

RUN apt-get update && \
    apt-get install -y --no-install-recommends locales-all && \
    apt-get install -y --no-install-recommends wget ca-certificates && \
    wget https://github.com/supervc-stack/VectorChord/releases/download/${VCHORD}/postgresql-${PG_MAJOR}-vchord_${VCHORD}-1_$(dpkg --print-architecture).deb -P /tmp && \
    apt-get install -y postgresql-${PG_MAJOR}-pgvector && \
    apt-get install -y /tmp/postgresql-${PG_MAJOR}-vchord_${VCHORD}-1_$(dpkg --print-architecture).deb && \
    apt-get remove -y wget ca-certificates && \
    apt-get purge -y --auto-remove && \
    rm -rf /tmp/* /var/lib/apt/lists/*

RUN groupmod -g ${POSTGRES_GID} postgres && \
    usermod -u ${POSTGRES_UID} -g ${POSTGRES_GID} postgres

# 默认数据目录改用包管理器标准的 main 路径（对齐 pg_ctlcluster 布局），替代镜像默认的 docker 路径
ENV PGDATA /var/lib/postgresql/$PG_MAJOR/main

CMD ["postgres", "-c" ,"shared_preload_libraries=vchord,vector"]

