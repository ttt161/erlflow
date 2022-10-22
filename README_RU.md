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
Правила фильтрации и тегирования задаются в файле config/config.yml (путь может быть переопределен в sys.config через 
параметр config_path, подробное описание конфигурационного файла см. ниже). Для примера выше config.yml выглядит так:
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

При добавлении новых серверов, если они будут функционировать в тех же сетях, не потребуется правка конфигурационного 
файла, метрики будут появляться автоматически (хорошая практика, когда планирование сети и мониторинга идут рука об руку)))

Описание конфигурационного файла
=====

Конфигурационный файл по умолчанию config/config.yml (путь может быть переопределен в sys.config через параметр config_path). 
Он состоит из списка правил для обработки потоков. netflow пакет сравнивается с каждым правилом по порядку от первого к 
последнему и обрабатывается в соответствии с первым совпавшим правилом. Если параметры потока не совпали ни с одним 
правилом, то поток игнорируется.

Правило содержит имена параметров потока с условиями для сравнения и описание действия, если параметры потока 
соответствуют заданным условиям.
````
 ParamName:
   Operator: Value
````
Operator определяет как нужно сравнивать значение параметра потока с заданным Value. Для сравнения на совпадение Operator 
match, для сравнения на несовпадение - dismatch.

Обрабатываемые параметры потока:
- src_addr, адрес источника, в условии можно сравнить адрес на совпадение или несовпадение с ipv4 префиксом
Пример:
````
 src_addr:
   match: 10.0.0.0/24
````
- dst_addr, адрес назначения, условие задается аналогично src_addr
- src_port, порт источника, может принимать одно значение или диапазон, значение должно быть в диапазоне 1-65535
- dst_port, порт назначения, аналогично src_port
Пример:
````
 src_port:
   match: 10080
 dst_port:
   dismatch: 10010-10020
````
- port, альтернативный способ проверки номера порта для одноранговых взаимодействий, когда целевой порт может принадлежать не только 
серверу, а любой из взаимодействующих сторон. Вычисляется следующим образом: если min(src_port, dst_port) < min(ephemeral_ports), 
то port=min(src_port, dst_port) иначе (то есть если оба порта динамические) port=0. Диапазон динамических (ephemeral) портов
по умолчанию 49152-65535, но может быть переопределен в sys.config в параметре ephemeral_range ({ephemeral_range, {49152, 65535}}).
Условие задается аналогично src_port, dst_port
- proto, номер протокола, инкапсулируемого в IP, может принимать значения 1-252
- tos, тип сервиса, может принимать значения 0-255

Важно! В правиле обязательно должно быть задано условие хотя бы для одного параметра потока!

Действие определяет в какой метрике будет учитываться количество байт/пакетов, переданных в потоке. Для этого необходимо
задать суффикс для ключа метрики, определить список параметров потока, которые будут отображены в метки метрики, а также
указать дополнительны метки. Обязательным является только суффикс для ключа метрики.
Пример:
````
 action:
   key_suffix: _some_string
   attributes:
     - src_addr
     - dst_addr
   ext_attributes:
     label: value
````
Если attributes не определены, то по умолчанию будут использованы: src_addr, dst_addr, proto, port, tos.

Важно!!! Если вы задаете одинаковый key_suffix для нескольких правил, то значения attributes и ext_attributes в этих правилах
не должны отличаться. Если этого не сделать, то библиотека prometheus не сможет корректно обработать такие метрики.

Также action может принимать значение reject:
````
 action: reject
````
В этом случае информация о потоке будет проигнорирована.