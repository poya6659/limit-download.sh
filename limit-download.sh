#!/bin/bash

CONF_FILE="/etc/wireguard/wg0.conf"
IFACE="wg0"
RATE="15mbit"
CEIL="15mbit"
CLASSID_BASE=160

# ����� ���� ���� �������
if [[ ! -f "$CONF_FILE" ]]; then
    echo "? File tanzimat $CONF_FILE vojud nadarad."
    exit 1
fi

# ����� ���� qdisc � ����� �� �� ���� ����
if ! tc qdisc show dev $IFACE | grep -q "htb"; then
    tc qdisc add dev $IFACE root handle 1: htb default 30
    tc class add dev $IFACE parent 1: classid 1:1 htb rate 1000mbit
fi

# ������� IP��� ����� �� ���� �������
ips=$(grep -oP 'AllowedIPs\s*=\s*\K\d+\.\d+\.\d+\.\d+' "$CONF_FILE" | sort | uniq)
if [[ -z "$ips" ]]; then
    echo "? Hich IP dar $CONF_FILE peyda nashod."
    exit 1
fi

# ������ IP��� ����� ����� ���
existing_filters=$(tc filter show dev $IFACE parent 1:0 | grep -oP 'match ip dst \K\d+\.\d+\.\d+\.\d+' | sort | uniq)
if [[ -z "$existing_filters" ]]; then
    echo "?? Hich filter ghabli baraye $IFACE vojud nadarad."
fi

# ����� ���� IP��� ����� �� ����� ������
declare -A existing_ips
for ip in $existing_filters; do
    existing_ips[$ip]=1
done

# ����� �������� classid �����
last_classid=$(tc class show dev $IFACE parent 1:1 | grep -oP '1:\K\d+' | sort -n | tail -1)
if [[ -z "$last_classid" ]]; then
    last_classid=$((CLASSID_BASE - 1))
fi
echo "?? Akharin classid estefade shode: $last_classid"

new_ips=0
for ip in $ips; do
    # ����� ���� ��� IP ����� ����� ��� ���
    if [[ -z "${existing_ips[$ip]}" ]]; then
        classid_num=$((last_classid + new_ips + 1))
        classid_hex=$(printf "%x" $classid_num)
        
        # ���� ���� ������ ����
        if tc class add dev $IFACE parent 1:1 classid 1:$classid_hex htb rate $RATE ceil $CEIL 2>/dev/null; then
            # ���� ���� ������ �����
            if tc filter add dev $IFACE protocol ip parent 1:0 prio 1 u32 match ip dst $ip flowid 1:$classid_hex 2>/dev/null; then
                echo "??? Mahdudiat baraye IP jadid $ip dar kelas 1:$classid_hex"
                ((new_ips++))
            else
                # ��� ���� �� ���� Ԙ�� ������ �����
                tc class del dev $IFACE classid 1:$classid_hex 2>/dev/null
            fi
        fi
    fi
done

if [[ $new_ips -eq 0 ]]; then
    echo "?? Hich IP jadid baraye mahdudiat peyda nashod."
else
    echo "? Mahdudiat $RATE baraye $new_ips client jadid anjam shod."
fi