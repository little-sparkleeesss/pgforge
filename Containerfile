ARG PG_MAJOR=18

# Debian 发行版代号，同时决定下面两个 FROM，不能只改一个：
# 上游镜像的 /etc/apt/sources.list.d/pgdg.list 里写死了对应的 apt 源代号
#（bookworm 变体 -> bookworm-pgdg，trixie 变体 -> trixie-pgdg），
# 而那个文件是从上游 COPY 过来的。base 和上游变体一旦错位，apt 不会报错，
# 会静默把另一个发行版编的包装进来。
#
# CI 会拉 postgres:${PG_MAJOR} 读出它实际基于哪个代号，然后作为 build-arg 传进来，
# 所以正常构建不用管这个默认值——它只用于本地直接构建（docker build / podman build）。
# 本地构建想和 CI 结果一致，就把它改成 postgres:${PG_MAJOR} 当前用的那个代号。
#
# 注意：跟上游走意味着 base 的 glibc 也跟着变（bookworm 2.36 → trixie 2.41）。
# 若已有数据库是在旧 glibc 下建的，换 base 后文本索引可能受影响，按 REINDEX /
# REFRESH COLLATION 流程处理。要钉死不动就把 CI 传的 build-arg 去掉。
ARG DEBIAN_SUITE=trixie

# 留空 = 始终装 PGDG 上最新的 18.x（重建即拿到安全更新）。
# 需要可复现构建时传 --build-arg PG_VERSION=18.6-1.pgdg12+2。
ARG PG_VERSION=

# 同上：留空 = 装最新的 postgresql-18-pgauditlogtofile。
# 想锁特定版本就传 --build-arg PGAUDITLOGTOFILE_VERSION=1.8.5-1.pgdg12+1。
ARG PGAUDITLOGTOFILE_VERSION=

# ── 只作为「上游文件的来源」，最终镜像不包含它的任何层 ──
FROM postgres:${PG_MAJOR}-${DEBIAN_SUITE} AS upstream

# ── 运行期 ──
FROM debian:${DEBIAN_SUITE}-slim

ARG PG_MAJOR
ARG PG_VERSION
ARG VCHORD
ARG PGAUDITLOGTOFILE_VERSION
ARG POSTGRES_UID=999
ARG POSTGRES_GID=999

# 需要额外生成的 locale，空格分隔 "<语言>.<字符集>"。默认保留英文 + CJK 全覆盖。
# 基础镜像层里已用 locale-gen 生成 en_US.UTF-8，C.UTF-8 由 glibc 自带，都不占额外空间。
# 不装 locales-all：它会带进 499 个 locale、约 216MB 未压缩（压缩后约 64MB），
# 而下面这 5 个 CJK 只花 5.2MB 未压缩——localedef 会把它们追加进共享的 locale-archive，
# 公共数据自动去重。（locales-all 内部是符号链接去重，不能"留几个删其它"，只能按需生成。）
# 确实需要任意 locale（多租户、per-DB 指定 lc_time 等）就把 locales-all 装回来。
ARG EXTRA_LOCALES="zh_CN.UTF-8 zh_TW.UTF-8 zh_HK.UTF-8 ja_JP.UTF-8 ko_KR.UTF-8"

ENV PG_MAJOR=${PG_MAJOR} \
    LANG=en_US.utf8 \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/lib/postgresql/${PG_MAJOR}/bin \
    PGDATA=/var/lib/postgresql/${PG_MAJOR}/main

# keyring / apt 源 / entrypoint 脚本 / gosu 全部从上游取，上游改了这里自动跟着走，
# 不用手抄。上游若挪走这些文件，构建会在这里直接失败而不是静默出错。
COPY --from=upstream /usr/local/share/keyrings/postgres.gpg.asc /usr/local/share/keyrings/
COPY --from=upstream /etc/apt/sources.list.d/pgdg.list /etc/apt/sources.list.d/
COPY --from=upstream /usr/local/bin/docker-entrypoint.sh /usr/local/bin/
COPY --from=upstream /usr/local/bin/docker-ensure-initdb.sh /usr/local/bin/
COPY --from=upstream /usr/local/bin/docker-enforce-initdb.sh /usr/local/bin/
COPY --from=upstream /usr/local/bin/gosu /usr/local/bin/

# RUN sed -i 's/deb.debian.org/mirrors.ustc.edu.cn/g' /etc/apt/sources.list.d/debian.sources

RUN set -eux; \
    os_suite="$(sed -nE 's|^VERSION_CODENAME=(.*)|\1|p' /etc/os-release)"; \
    pgdg_suite="$(sed -nE 's|.*/apt ([a-z]+)-pgdg .*|\1|p' /etc/apt/sources.list.d/pgdg.list | head -1)"; \
    if [ -z "$os_suite" ] || [ "$os_suite" != "$pgdg_suite" ]; then \
        echo "底层系统是 '${os_suite}'，但 COPY 自上游的 PGDG 源指向 '${pgdg_suite}-pgdg'。"; \
        echo "两个 FROM 必须用同一个 Debian 代号，检查 Containerfile 顶部的 ARG DEBIAN_SUITE。"; \
        exit 1; \
    fi; \
    apt-get update; \
    pkg="postgresql-${PG_MAJOR}"; \
    if [ -n "$PG_VERSION" ]; then pkg="$pkg=$PG_VERSION"; fi; \
    audit="postgresql-${PG_MAJOR}-pgauditlogtofile"; \
    if [ -n "$PGAUDITLOGTOFILE_VERSION" ]; then audit="$audit=$PGAUDITLOGTOFILE_VERSION"; fi; \
    getent group postgres >/dev/null || groupadd -r postgres --gid=${POSTGRES_GID}; \
    getent passwd postgres >/dev/null || useradd -r -g postgres --uid=${POSTGRES_UID} \
        --home-dir=/var/lib/postgresql --shell=/bin/bash postgres; \
    apt-get install -y --no-install-recommends \
        postgresql-common libnss-wrapper xz-utils zstd less wget ca-certificates; \
    sed -ri 's/#(create_main_cluster) .*$/\1 = false/' /etc/postgresql-common/createcluster.conf; \
    apt-get install -y --no-install-recommends "$pkg"; \
    apt-get install -y --no-install-recommends \
        postgresql-${PG_MAJOR}-pgvector \
        postgresql-${PG_MAJOR}-pgaudit \
        "$audit"; \
    wget -q -P /tmp "https://github.com/supervc-stack/VectorChord/releases/download/${VCHORD}/postgresql-${PG_MAJOR}-vchord_${VCHORD}-1_$(dpkg --print-architecture).deb"; \
    apt-get install -y --no-install-recommends "/tmp/postgresql-${PG_MAJOR}-vchord_${VCHORD}-1_$(dpkg --print-architecture).deb"; \
    echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen; \
    locale-gen; \
    for loc in ${EXTRA_LOCALES}; do localedef -i "${loc%%.*}" -f "${loc#*.}" "$loc"; done; \
    install --directory --owner postgres --group postgres --mode 1777 /var/lib/postgresql; \
    install --directory --owner postgres --group postgres --mode 3777 /var/run/postgresql; \
    mkdir /docker-entrypoint-initdb.d; \
    dpkg-divert --add --rename --divert "/usr/share/postgresql/postgresql.conf.sample.dpkg" "/usr/share/postgresql/${PG_MAJOR}/postgresql.conf.sample"; \
    cp -v /usr/share/postgresql/postgresql.conf.sample.dpkg /usr/share/postgresql/postgresql.conf.sample; \
    ln -sv ../postgresql.conf.sample "/usr/share/postgresql/${PG_MAJOR}/"; \
    sed -ri "s!^#?(listen_addresses)\s*=\s*\S+.*!\1 = '*'!" /usr/share/postgresql/postgresql.conf.sample; \
    grep -F "listen_addresses = '*'" /usr/share/postgresql/postgresql.conf.sample; \
    apt-get purge -y --auto-remove wget ca-certificates; \
    rm -f /tmp/*.deb; \
    rm -rf /var/lib/apt/lists/*; \
    postgres --version; \
    locale -a

RUN set -eux; \
    entry=/usr/local/bin/docker-entrypoint.sh; \
    sed -ri 's|\[ "\$PGDATA" = "/var/lib/postgresql/\$PG_MAJOR/docker" \]|[ "${PGDATA#/var/lib/postgresql/}" != "$PGDATA" ]|' "$entry"; \
    grep -qF '[ "${PGDATA#/var/lib/postgresql/}" != "$PGDATA" ]' "$entry"; \
    bash -n "$entry"

VOLUME /var/lib/postgresql
EXPOSE 5432
STOPSIGNAL SIGINT
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["postgres", "-c", "shared_preload_libraries=pgaudit,pgauditlogtofile,vchord"]
