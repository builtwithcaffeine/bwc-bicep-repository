# Client Config Setup

> [!IMPORTANT]
> Elevate to **SUDO** for the next steps.

``` bash
sudo -s
```

> [!NOTE]
> You will need the Customer Name and Certificate Authority Password


Change directory to:

```
cd /etc/openvpn/easy-rsa
```

Update the below code snippet

``` bash
customerName='client-bwccloud'
./easyrsa gen-req $customerName nopass
./easyrsa sign-req client $customerName
```
<br>

> [!NOTE]
> You will need the `Certificate Authority` Pass Key for the Signing Request

Once created the files will be located under:
* CA : /etc/openvpn/easy-rsa/pki/ca.crt
* CA Key: /etc/openvpn/easy-rsa/pki/private/ca.key
* req: /etc/openvpn/easy-rsa/pki/reqs/${customerName}.req
* key: /etc/openvpn/easy-rsa/pki/private/${customerName}.key
* Cer: /etc/openvpn/easy-rsa/pki/issued/${customerName}.crt
* TA: /etc/openvpn/ta.key
