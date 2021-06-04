Скрипты сборки Kali-ARM
======================

- Эти скрипты были протестированы только на 32- и 64-разрядных установках Kali Linux после того, как были установлены все зависимости.
- Убедитесь, что вы сначала запустили сценарий `build-deps.sh`, который устанавливает все необходимые зависимости.

** _ ЕСЛИ ВЫ СОЗДАЕТЕ ВМ, ВАМ НУЖНО ВЫДЕЛАТЬ НЕ МЕНЬШЕ 8 ГБ ОЗУ ИЛИ ИСПОЛЬЗОВАТЬ ФАЙЛ SWAP _ **

Пример рабочего процесса будет похож на (armhf):

`` ''
mkdir -p ~ / рука-материал /
cd ~ / arm-stuff /
git clone https://gitlab.com/kalilinux/build-scripts/kali-arm ~ / arm-stuff / kali-arm /
cd ~ / arm-stuff / kali-arm /
./build-deps.sh
./pinebook-pro.sh 2021.2
`` ''

Если вы используете 32-разрядную версию, после того, как скрипт завершит работу, у вас будет файл изображения, расположенный в ~ / arm-stuff / kali-arm / `kali-linux-2021.2-pinebook-pro.img`.

32-битной версии не хватает памяти для сжатия изображения.
** _ Вам нужно будет использовать собственное предпочтительное сжатие, если вы хотите его распространять ._ **

В 64-битных системах после завершения работы скрипта у вас будут файлы изображений, расположенные в `~ / arm-stuff / kali-arm /`, под названием `kali-linux-2021.2-pinebook-pro.img.xz`.

**_CICADA3301_**

# kali_linux_all
Запуск Kali Linux В Разных Системах от Windiws 10 до Браузерного режима
Кали в браузере (Гуакамоле)
Вы можете взаимодействовать с Kali различными способами, например, сидя прямо у консоли (чаще всего для графического восприятия), или используя Kali удаленно через SSH (что дает вам доступ к командной строке). В качестве альтернативы вы можете настроить VNC, который обеспечит удаленный графический доступ (пожалуйста, убедитесь, что это безопасно, так как VNC прослушивает петлевую проверку и перенаправляет порт через SSH). Другой подход - взаимодействовать с Kali в браузере, вместо того, чтобы устанавливать необходимые клиенты VNC.

Это руководство охватывает Apache Guacamole, но у нас также есть другое руководство noVNC . У каждого есть свои плюсы и минусы. Guacamole - более полное решение, оно поддерживает несколько протоколов и позволяет клиентам подключаться к нему с центральной страницы с аутентификацией пользователя.

Apache Guacamole не входит в пакет Debian и содержит различные шаги для завершения настройки (или вы можете использовать образ докера ). В процессе установки есть автоматизированный сценарий.

Первый этап - скачать скрипт:

     kali@kali:~$ sudo apt update
     kali@kali:~$
     kali@kali:~$ sudo apt install -y git
     kali@kali:~$
     kali@kali:~$ git clone https://github.com/MysticRyuujin/guac-install.git /tmp/guac-install
     kali@kali:~$
     
ВАЖНЫЙ! Если вы находитесь в восточном часовом поясе, вам придется перейти на другой. В Apache есть ошибка, из-за которой EDT не рассматривается как действительный часовой пояс.

Чтобы решить эту проблему, мы изменим наш часовой пояс на Центральное время.

     kali@kali:~$ sudo rm /etc/localtime
     kali@kali:~$
     kali@kali:~$ sudo ln -s /usr/share/zoneinfo/US/Central /etc/localtime
Мы собираемся выполнить «автономную» установку, если нет отдельного хоста базы данных MySQL, а также не включен какой-либо MFA (поскольку мы собираемся скрыть это за туннелем SSH) :

     kali@kali:~$ cd /tmp/guac-install/
     kali@kali:/tmp/guac-install$ sudo ./guac-install.sh --nomfa --installmysql --mysqlpwd S3cur3Pa$$w0rd --guacpwd P@s$W0rD
...
Cleanup install files...

Installation Complete
- Visit: http://localhost:8080/guacamole/
- Default login (username/password): guacadmin/guacadmin
***Be sure to change the password***.

     kali@kali:/tmp/guac-install$
Можем оперативно проверить, все ли услуги устраивают:

     kali@kali:/tmp/guac-install$ systemctl status tomcat9 guacd mysql
     ● tomcat9.service - Apache Tomcat 9 Web Application Server
          Loaded: loaded (/lib/systemd/system/tomcat9.service; enabled; vendor preset: disabled)
          Active: active (running) since Thu 2020-03-05 17:39:38 GMT; 1min 14s ago
            Docs: https://tomcat.apache.org/tomcat-9.0-doc/index.html
        Main PID: 33192 (java)
           Tasks: 47 (limit: 19107)
          Memory: 454.8M
          CGroup: /system.slice/tomcat9.service
                  └─33192 /usr/lib/jvm/default-java/bin/java -Djava.util.logging.config.file=/var/lib/tomcat9/conf/logging.properties -Djava.util.logging.manager=org.apache.juli.ClassLoaderLogManager -Djava.a>

     ● guacd.service - LSB: Guacamole proxy daemon
          Loaded: loaded (/etc/init.d/guacd; generated)
          Active: active (running) since Thu 2020-03-05 14:04:34 GMT; 3h 36min ago
            Docs: man:systemd-sysv-generator(8)
           Tasks: 1 (limit: 19107)
          Memory: 11.5M
          CGroup: /system.slice/guacd.service
                  └─991 /usr/local/sbin/guacd -p /var/run/guacd.pid

     Warning: Journal has been rotated since unit was started. Log output is incomplete or unavailable.

     ● mysql.service - LSB: Start and stop the mysql database server daemon
          Loaded: loaded (/etc/init.d/mysql; generated)
          Active: active (running) since Thu 2020-03-05 17:39:46 GMT; 1min 6s ago
            Docs: man:systemd-sysv-generator(8)
           Tasks: 34 (limit: 19107)
          Memory: 88.9M
          CGroup: /system.slice/mysql.service
                  ├─33670 /bin/sh /usr/bin/mysqld_safe
                  ├─33787 /usr/sbin/mysqld --basedir=/usr --datadir=/var/lib/mysql --plugin-dir=/usr/lib/x86_64-linux-gnu/mariadb19/plugin --user=mysql --skip-log-error --pid-file=/run/mysqld/mysqld.pid --soc>
                  └─33788 logger -t mysqld -p daemon error
     kali@kali:/tmp/guac-install$
     kali@kali:/tmp/guac-install$ sudo ss -antup | grep "mysqld\|guacd\|java"
     tcp    LISTEN  0       80                 127.0.0.1:3306         0.0.0.0:*       users:(("mysqld",pid=33787,fd=21))
     tcp    LISTEN  0       5                  127.0.0.1:4822         0.0.0.0:*       users:(("guacd",pid=991,fd=4))
     tcp    LISTEN  0       100                        *:8080               *:*       users:(("java",pid=33192,fd=36))
     kali@kali:/tmp/guac-install$
Все службы работают правильно.

Затем нужно включить службу VNC на Kali.

Мы собираемся использовать TigerVNC.

     kali@kali:~$ sudo apt install -y tigervnc-standalone-server
     kali@kali:~$
     kali@kali:~$ mkdir -p ~/.vnc/
     kali@kali:~$
     kali@kali:~$ wget https://gitlab.com/kalilinux/nethunter/build-scripts/kali-nethunter-project/-/raw/master/nethunter-fs/profiles/xstartup -O ~/.vnc/xstartup
     kali@kali:~$
     kali@kali:~$ vncserver :1
Далее мы собираемся перейти в админ-панель гуакамоле и создать новое соединение.

Сначала мы нажимаем «Настройки» в верхнем правом раскрывающемся меню.



Затем мы перейдем на вкладку «Подключения» и нажмем «Новое подключение». Мы заполним эти поля ниже:



Мы обязательно устанавливаем «Глубину цвета», так как мы делаем это, чтобы цвета проходили правильно. При неправильной настройке некоторые оттенки серого могут стать фиолетовыми или другими.

После всего этого вы можете перейти в «Домой» в верхнем правом раскрывающемся списке и щелкнуть новое соединение.



#    Kali в браузере (noVNC)

Вы можете взаимодействовать с Kali различными способами, например, сидя прямо у консоли (чаще всего для графического восприятия), или используя Kali удаленно через SSH (что дает вам доступ к командной строке). В качестве альтернативы вы можете настроить VNC, который обеспечит удаленный графический доступ (пожалуйста, убедитесь, что это безопасно, так как VNC прослушивает петлевую проверку и перенаправляет порт через SSH). Другой подход - взаимодействовать с Kali в браузере, вместо того, чтобы устанавливать необходимые клиенты VNC.

Это руководство охватывает noVNC, но у нас также есть другое руководство для Apache Guacamole . У каждого есть свои плюсы и минусы. NoVNC - это более легкий подход, поскольку он требует меньше услуг (меньше накладных расходов), что позволяет быстро получить решение «одноразовое подключение».

Сначала мы обновляем, а затем устанавливаем необходимые пакеты (мы выбрали x11vnc в качестве нашего решения VNC. Вы можете переключить его на любой сервис VNC по вашему желанию. Однако поддержка может быть разной) :

     kali@kali:~$ sudo apt update
     kali@kali:~$
     kali@kali:~$ sudo apt install -y novnc x11vnc
     kali@kali:~$
Затем мы запускаем сеанс VNC. Мы решили сделать это только с обратной связью, что сделало ее более безопасной (мы пропускаем x11vncвстроенную функцию HTTP. Для этого требуется Java, и мы не хотим устанавливать ее ни на одном из наших клиентов, поскольку noVNC предоставляет возможности HTML5. ) :

     kali@kali:~$ x11vnc -display :0 -autoport -localhost -nopw -bg -xkb -ncache -ncache_cr -quiet -forever

     The VNC desktop is:      localhost:0
     PORT=5900
     kali@kali:~$
ПРИМЕЧАНИЕ. Мы используем display :0текущий рабочий стол.

Мы можем дважды проверить, какой порт используется для VNC:

     kali@kali:~$ ss -antp | grep vnc
     LISTEN    0         32                127.0.0.1:5900            0.0.0.0:*        users:(("x11vnc",pid=8056,fd=8))
     LISTEN    0         32                    [::1]:5900               [::]:*        users:(("x11vnc",pid=8056,fd=9))
     kali@kali:~$
Мы видим, что он использует порт 5900.

После этого мы запускаем noVNC (это откроется 8081/TCP):

     kali@kali:~$ /usr/share/novnc/utils/launch.sh --listen 8081 --vnc localhost:5900
<p align="center">
  <img src="https://github.com/Cicadadenis/kali_linux_all/blob/main/bsp/img/novnc-kali-in-browser-1.png">
</p

А еще лучше включите SSH:

     kali@kali:~$ sudo systemctl enable ssh --now
     kali@kali:~$
Затем на удаленном компьютере введите SSH в вашу настройку Kali (вам может потребоваться сначала включить переадресацию портов)

     $ ssh kali@192.168.13.37 -L 8081:localhost:8081
     
<p align="center">
  <img src="https://github.com/Cicadadenis/kali_linux_all/blob/main/bsp/img/novnc-kali-in-browser-2.png">
</p
