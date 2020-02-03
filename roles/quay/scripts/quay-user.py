#!/usr/bin/env python3

import requests
import json
import sys
import urllib3
urllib3.disable_warnings()

class UnexpectedApiResponse(Exception):
    pass

class Quay(object):
    def __init__(self, base_url, username, password):
        self.url = f'{base_url}/api/v1'
        self.sign_in(base_url, username, password)

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, exc_traceback):
        self.sign_out()

    def sign_in(self, base_url, username, password):
        self.session = requests.session()
        self.session.verify = False
        load_login = self.session.get(base_url)
        for line in load_login.text.split('\n'):
            if '__token' in line:
                token = line.split("'")[1]
                break
        self.session.headers.update(
            {
                'Content-type': 'application/json',
                'Accept': 'text/plain',
                'X-CSRF-Token': token
            }
        )
        return self.api_req('post', 'signin',
                            data={'username': username, 'password': password})

    def sign_out(self):
        ret_val = self.api_req('post', 'signout')
        self.session.close()
        return ret_val

    def api_req(self, method, endpoint, data=None):
        method = getattr(self.session, method)

        if data is None:
            ret_val = method(f'{self.url}/{endpoint}')
        else:
            ret_val = method(f'{self.url}/{endpoint}', data=json.dumps(data))

        if ret_val.status_code != 200:
            raise UnexpectedApiResponse(ret_val.text)
        token = ret_val.headers.get('X-Next-CSRF-Token')
        if token is not None:
            self.session.headers.update({'X-CSRF-Token': token})
        return ret_val

    def add_user(self, username, password):
        try:
            return self.api_req('post', 'user', data={'username': username,
                                                      'password': password})
        except UnexpectedApiResponse as e:
            sys.stderr.write(f'Error adding {username}, response:\n')
            sys.stderr.write(
                '  ' + json.loads(str(e)).get('error_message') + '\n'
            )
            sys.stderr.flush()
            pass

if __name__ == '__main__':
    from argparse import ArgumentParser
    description = """
    Creates local database users in a Quay instance when provided with superuser
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
        help='the URL of Quay, not including anything after the TLD'
    )
    parser.add_argument(
        '--login-username', '-U', required=True,
        help='the username with which to log in to Quay'
    )
    parser.add_argument('--login-password', '-P', required=True,
                        help='the password for the login user')
    parser.add_argument(
        '--username', '-u', action='append',
        help=('a username to add to Quay '
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
        _ = requests.get(args.url, verify=False)
    except requests.exceptions.SSLError:
        sys.stderr.write(f'{args.url} appears to be offline and is not '
                         'responding to requests.\n')
        sys.stderr.flush()
        exit(1)

    with Quay(args.url, args.login_username, args.login_password) as quay:
        for username, password in zip(args.username, args.password):
            if quay.add_user(username, password):
                print(f'{username} added')
