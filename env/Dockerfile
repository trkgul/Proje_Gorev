FROM python:3.6.8

WORKDIR /app

ADD . /app

RUN pip install -r requirements.txt

CMD ["uwsgi", "config.ini"]