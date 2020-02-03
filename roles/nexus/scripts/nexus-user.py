#!/usr/bin/env python3

import requests
import json
import sys
import urllib3
from base64 import b64encode
urllib3.disable_warnings()

class UnexpectedApiResponse(Exception):
    pass

class Nexus(object):
    def __init__(self, base_url, username, password):
        self.url = f'{base_url}/service/rest'
        self.username = username
        self.password = password
        self.sign_in()

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, exc_traceback):
        self.sign_out()

    def sign_in(self):
        self.session = requests.session()
        self.session.verify = False
        self.session.headers.update(
            {
                'Content-type': 'application/json',
                'Accept': 'application/json'
            }
        )
        b64_username = b64encode(self.username.encode('utf-8'))
        b64_password = b64encode(self.password.encode('utf-8'))
        login_data = {
            'u': b64_username.decode('ascii'),
            'p': b64_password.decode('ascii')
        }
        token = json.loads(self.api_req('post', 'wonderland/authenticate',
                                        data=login_data).text).get('t')
        self.session.headers.update({'X-NX-AuthTicket': token})

    def sign_out(self):
        self.session.close()

    def api_req(self, method, endpoint, data=None):
        method = getattr(self.session, method)

        kwargs = {}
        if data is not None:
            kwargs['data'] = json.dumps(data)

        ret_val = method(f'{self.url}/{endpoint}',
                         auth=(self.username, self.password), **kwargs)

        if ret_val.status_code != 200:
            raise UnexpectedApiResponse(ret_val.text)
        return ret_val

    def list_users(self):
        return json.loads(self.api_req('get', 'beta/security/users').text)

    def search_users(self, user):
        return json.loads(
            self.api_req('get', f'beta/security/users?userId={user}').text
        )

    def add_user(self, username, password):
        data = {
            'userId': username,
            'firstName': username,
            'lastName': username,
            'password': password,
            'emailAddress': f'{username}@example.com',
            'status': 'active',
            'roles': ['nx-admin']
        }
        return json.loads(
            self.api_req('post', 'beta/security/users', data=data).text
        )


if __name__ == '__main__':
    from argparse import ArgumentParser
    description = """
    Creates local database users in a Nexus instance when provided with admin
    credentials and the base URL of the web interface. Only uses one API session
    to do so and reuses it for all requests.
    """
    epilog = """
    NOTE: the number of users and passwords to create must be equal. You can
    specify them in any order you wish, but they will be paired up in the order
    in which they were received for creation.
    """
    parser = ArgumentParser(description=description, epilog=epilog)
    parser.add_argument(
        'url', metavar='URL',
        help='the URL of Nexus, not including anything after the TLD'
    )
    parser.add_argument(
        '--login-username', '-U', required=True,
        help='the username with which to log in to Nexus'
    )
    parser.add_argument('--login-password', '-P', required=True,
                        help='the password for the login user')
    parser.add_argument(
        '--username', '-u', action='append',
        help=('a username to add to Nexus '
              '(may be specified multiple times)')
    )
    parser.add_argument(
        '--password', '-p', action='append',
        help=('a password for the last username provided '
              '(may be specified multiple times)')
    )
    args = parser.parse_args()

    if len(args.username) != len(args.password):
        sys.stderr.write('You must provide the same number of usernames and '
                         'passwords in order to create users with this tool.\n')
        sys.stderr.flush()
        exit(1)
    try:
        if requests.get(args.url, verify=False).status_code != 200:
            sys.stderr.write(f'{args.url} appears to be offline and is not '
                             'responding to requests.\n')
            sys.stderr.flush()
            exit(1)
    except requests.exceptions.SSLError:
        sys.stderr.write(f'{args.url} appears to be offline and is not '
                         'responding to requests.\n')
        sys.stderr.flush()
        exit(1)

    exit_code = 0
    with Nexus(args.url, args.login_username, args.login_password) as nexus:
        for username, password in zip(args.username, args.password):
            if nexus.search_users(username):
                print(f'{username}: ok')
            else:
                if nexus.add_user(username, password):
                    print(f'{username}: added')
                else:
                    exit_code += 1
                    print(f'{username}: failed')
    exit(exit_code)
