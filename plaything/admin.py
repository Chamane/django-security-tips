from django.contrib import admin
from plaything import models

from django import forms
from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as BaseUserAdmin
from django.contrib.auth.forms import UserCreationForm
from django.contrib.auth.forms import UserChangeForm

class CustomUserCreationForm(UserCreationForm):
    class Meta(UserCreationForm.Meta):
        model = models.CustomUser

class CustomUserChangeForm(UserChangeForm):
    class Meta(UserChangeForm.Meta):
        model = models.CustomUser

class UserAdmin(BaseUserAdmin):
    form = CustomUserChangeForm
    add_form = CustomUserCreationForm

admin.site.register(models.CustomUser, UserAdmin)
admin.site.register(models.IntegerTuple)
