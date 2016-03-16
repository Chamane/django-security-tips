from django.db import models

# Create your models here.
class IntegerTuple(models.Model):
    first = models.IntegerField(default=2)
    second = models.IntegerField(default=4)
    third = models.IntegerField(default=6)
