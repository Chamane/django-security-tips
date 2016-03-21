from django.db import models
from django.db import connection
from django.contrib.auth.models import AbstractUser
from django.contrib.auth.hashers import make_password
from django.utils.crypto import get_random_string

class IntegerTuple(models.Model):
    first = models.IntegerField(default=2)
    second = models.IntegerField(default=4)
    third = models.IntegerField(default=6)

class CustomUser(AbstractUser):
    def make_random_password(self):
        length = 35
        allowed_chars='abcdefghjkmnpqrstuvwxyz' + 'ABCDEFGHJKLMNPQRSTUVWXYZ' + '23456789'
        return get_random_string(length, allowed_chars)

    def save(self, *args, **kwargs):
        update_pw = ('update_fields' not in kwargs or 'password' in kwargs['update_fields']) and '$' in self.password
        if update_pw:
            algo, iterations, salt, pw_hash = self.password.split('$', 3)
            # self.password should be unique anyway for get_session_auth_hash()
            self.password = self.make_random_password()

        super(CustomUser, self).save(*args, **kwargs)
        if update_pw:
            cursor = connection.cursor()
            cursor.execute("SELECT auth_schema.insert_or_update_password(%d, '%s', '%s');" % (self.id, salt, pw_hash))
        return

    def check_password(self, raw_password):
        cursor = connection.cursor()
        cursor.execute("SELECT auth_schema.get_salt(%d);" % self.id)
        salt = cursor.fetchone()[0]

        algo, iterations, salt, pw_hash = make_password(raw_password, salt=salt).split('$', 3)
        cursor.execute("SELECT auth_schema.check_password(%d, '%s');" % (self.id, pw_hash))
        pw_correct = cursor.fetchone()[0]
        return bool(pw_correct)
