FROM perl:5

RUN cpanm \
	Text::CSV \
	URI::Escape \
	DBI \
	MIME::Lite

RUN cpanm DBD::MariaDB

RUN apt-get -y update && \
    apt-get install -y msmtp gettext-base lynx curl ; \
    apt-get clean ; \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

COPY mailtool.pl /usr/local/bin/
COPY msmtprc /usr/local/share/etc-templates/
COPY entrypoint.sh /

ENTRYPOINT [ "/entrypoint.sh" ]

CMD [ "mailtool.pl" ]

