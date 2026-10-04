## Creds

Supply an Opaque Secret named `democratic-csi-mutual-chap` in namespace
`democratic-csi`

| Key | Value |
| --- | --- |
| `userid` | Client username |
| `password` | Client password |
| `mutual_userid` | Storage username |
| `mutual_password` | Storage password |
| `node-db.node.session.auth.authmethod` | `CHAP` |
| `node-db.node.session.auth.username` | Same value as `userid` |
| `node-db.node.session.auth.password` | Same value as `password` |
| `node-db.node.session.auth.username_in` | Same value as `mutual_userid` |
| `node-db.node.session.auth.password_in` | Same value as `mutual_password` |

