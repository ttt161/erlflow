Обзор
=====
erlflow предназначен не столько для сбора статистики по всем сетевым соединениям (хотя и это возможно), сколько для 
отслеживания определенных сетевых взаимодействий и группировки информации от множества netflow потоков в конкретные 
метрики по определенному правилу. 

Постановка задачи
=====
В протоколе netflow (здесь и далее имеется в виду netflow v5) поток является короткоживущей сущностью, которая однозначно 
идентифицируется по следующим параметрам:
- адрес источника
- адрес назначения
- порт источника
- порт назначения
- протокол, инкапсулированный в IP
- тип сервиса
- штамп времени первого пакета в потоке

Очевидно, что при регулярном взаимодействии одних и тех же сетевых сущностей (например сервисов) будет всегда меняться 
штамп времени первого пакета, а также, как правило, один из портов взаимодействия. Даже если опустить штамп времени и 
просто отобразить остальные параметры потока в метки метрики, то будет создаваться множество временных рядов, что создает 
неудобства при дальнейшей обработке информации. Гораздо более удобным представляется введение понятия 
"направление взаимодействия", которое, в зависимости от задачи, может расширять понятие "потока". Например, можно считать 
все пакеты/байты, переданные между хостами, без учета остальных параметров, или учесть пакеты/байты переданные одним 
прилижением в одной метрике, а остальные учесть в другой или вообще не учитывать. 

Пример:
Допустим имеется сеть из нескольких инстансов SIP-серверов. Сервера взаимодействую по "внутренней" сети 100.127.0.0/24, 
для установления связи между собой используют протокол TCP и порт 5080, а для медиа-трафика UDP и диапазон портов 
40000-41900. Клиенты устанавливают соединения на "внешние" адреса (например 88.127.127.0/24) и UDP порт 5060, для 
медиа-трафика используется диапазон портов 40000-40100. Задача: отслеживать нагрузку на сеть по всем межсерверным 
соединениям попарно, нагрузку от клиентов суммировать по каждому серверу отдельно.

![scheme](https://codeberg.org/ttt161/erlflow/src/branch/ERLFLOW-3/pic/scheme.png)

Решение
=====
Для решения задачи нам нужно описать правила фильтрации потоков, а также правила формирования меток для метрик.

Фильтр для межсерверного взаимодействие описывается следующим набором условий:
```
src_addr=100.127.0.0/24 dst_addr=100.127.0.0/24 proto=tcp port=5080 (параметр port описан ниже)
src_addr=100.127.0.0/24 dst_addr=100.127.0.0/24 proto=udp src_port=40000-41900 dst_port=40000-41900
```
Для попадания статистики переданных пакетов/байт в одну метрику мы должны оставить значимые параметры 
(src_addr, dst_addr, так как задача учесть все взаимодействия попарно) и исключить динамически меняющиеся 
(proto, port, src_port, dst_port, tos). Вместо исключенных параметров необходимо добавить дополнительную метку (или метки), 
которые позволят идентифицировать метрику, как взаимодействие SIP серверов, например, application="SIP",direction="service-service"

Фильтр для взаимодействия клиент -> сервер:
```
src_addr!=88.127.127.0/24 dst_addr=88.127.127.0/24 proto=udp dst_port=5060
src_addr!=88.127.127.0/24 dst_addr=88.127.127.0/24 proto=udp src_port=40000-41900 dst_port=40000-41900
```
Значимые параметры: dst_addr. Дополнительные метки: application="SIP",direction="client-service" 

Фильтр для взаимодействия сервер -> клиент:
```
src_addr=88.127.127.0/24 dst_addr!=88.127.127.0/24 proto=udp src_port=5060
src_addr=88.127.127.0/24 dst_addr!=88.127.127.0/24 proto=udp src_port=40000-41900 dst_port=40000-41900
```
Значимые параметры: src_addr. Дополнительные метки: application="SIP",direction="service-client" 

Реализация
=====
Правила фильтрации и тегирования задаются в файле config/config.yml (может быть переопределен в sys.config через параметр config_path)
Для примера выше config.yml выглядит так:
```yml
- src_addr:
    match: 100.127.0.0/24
  dst_addr:
    match: 100.127.0.0/24
  proto:
    match: 6
  port:
    match: 5080
  action:
    key_suffix: _sip_srv
    attributes:
      - src_addr
      - dst_addr
    ext_attributes:
      application: SIP
      direction: service-service

- src_addr:
    match: 100.127.0.0/24
  dst_addr:
    match: 100.127.0.0/24
  proto:
    match: 17
  src_port:
    match: 40000-41900
  dst_port:
    match: 40000-41900
  action:
    key_suffix: _sip_srv
    attributes:
      - src_addr
      - dst_addr
    ext_attributes:
      application: SIP
      direction: service-service

- src_addr:
    dismatch: 88.127.127.0/24
  dst_addr:
    match: 88.127.127.0/24
  proto:
    match: 6
  port:
    match: 5060
  action:
    key_suffix: _sip_upstream
    attributes:
      - dst_addr
    ext_attributes:
      application: SIP
      direction: client-service

- src_addr:
    dismatch: 88.127.127.0/24
  dst_addr:
    match: 88.127.127.0/24
  proto:
    match: 17
  src_port:
    match: 40000-41900
  dst_port:
    match: 40000-41900
  action:
    key_suffix: _sip_upstream
    attributes:
      - dst_addr
    ext_attributes:
      application: SIP
      direction: client-service

- src_addr:
    match: 88.127.127.0/24
  dst_addr:
    dismatch: 88.127.127.0/24
  proto:
    match: 6
  src_port:
    match: 5060
  action:
    key_suffix: _sip_downstream
    attributes:
      - src_addr
    ext_attributes:
      application: SIP
      direction: service-client

- src_addr:
    match: 88.127.127.0/24
  dst_addr:
    dismatch: 88.127.127.0/24
  proto:
    match: 17
  src_port:
    match: 40000-41900
  dst_port:
    match: 40000-41900
  action:
    key_suffix: _sip_downstream
    attributes:
      - src_addr
    ext_attributes:
      application: SIP
      direction: service-client
```
Таким образом, для нашего примера независимо от того, сколько параллельных соединений установят сервера между собой и 
сколько бы ни было клиентских соединений мы получим 12 временных рядов (и еще 12 с ключом netflow_packets_sent_):
````
netflow_bytes_sent_sip_srv{src_addr="100.127.0.1",dst_addr="100.127.0.2",application="SIP",direction="service-service"}
netflow_bytes_sent_sip_srv{src_addr="100.127.0.1",dst_addr="100.127.0.3",application="SIP",direction="service-service"}
netflow_bytes_sent_sip_srv{src_addr="100.127.0.2",dst_addr="100.127.0.1",application="SIP",direction="service-service"}
netflow_bytes_sent_sip_srv{src_addr="100.127.0.2",dst_addr="100.127.0.3",application="SIP",direction="service-service"}
netflow_bytes_sent_sip_srv{src_addr="100.127.0.3",dst_addr="100.127.0.1",application="SIP",direction="service-service"}
netflow_bytes_sent_sip_srv{src_addr="100.127.0.3",dst_addr="100.127.0.2",application="SIP",direction="service-service"}

netflow_bytes_sent_sip_upstream{dst_addr="88.127.127.1",application="SIP",direction="client-service"}
netflow_bytes_sent_sip_upstream{dst_addr="88.127.127.2",application="SIP",direction="client-service"}
netflow_bytes_sent_sip_upstream{dst_addr="88.127.127.3",application="SIP",direction="client-service"}

netflow_bytes_sent_sip_downstream{src_addr="88.127.127.1",application="SIP",direction="service-client"}
netflow_bytes_sent_sip_downstream{src_addr="88.127.127.2",application="SIP",direction="service-client"}
netflow_bytes_sent_sip_downstream{src_addr="88.127.127.3",application="SIP",direction="service-client"}
````

![metrics](https://codeberg.org/ttt161/erlflow/src/branch/ERLFLOW-3/pic/metrics.png)

При добавлении новых серверов, если они будут функционировать в тех же сетях, не потребуется правка конфигурационного файла, метрики будут появляться автоматически (хорошая практика, когда планирование сети и мониторинга идут рука об руку)))

Описание конфигурационного файла
===



