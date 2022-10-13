#include "Python.h"
#include <dlfcn.h>
#include <stdio.h>

#ifdef SUFFIX
  #define openblas_get_config openblas_get_config64_
#endif

extern const char * openblas_get_config();

PyObject *
get_config(PyObject *self, PyObject *args) {
    const char * config = openblas_get_config();
    return PyUnicode_FromString(config);
}

PyObject*
open_so(PyObject *self, PyObject *args) {
    const char *utf8 = PyUnicode_AsUTF8(args);
    if (utf8 == NULL) {
        return NULL;
    }
    void *handle = dlopen(utf8, RTLD_GLOBAL | RTLD_NOW);
    if (handle == NULL) {
        PyErr_SetString(PyExc_ValueError, "Could not open SO");
        return NULL;
    }
    Py_RETURN_TRUE; 
}

static PyMethodDef InitMethods[] = {
    {"get_config",  get_config, METH_NOARGS,
     "Return openblas_get_config(), see https://github.com/xianyi/OpenBLAS/wiki/OpenBLAS-Extensions"},
    {"open_so", open_so, METH_O,
     "Use dlopen to load the shared object, which must exist"},
    {NULL, NULL, 0, NULL}        /* Sentinel */
};

static struct PyModuleDef initmodule = {
    PyModuleDef_HEAD_INIT,
    "_init_openblas",   /* name of module */
    NULL, /* module documentation, may be NULL */
    -1,       /* size of per-interpreter state of the module,
                 or -1 if the module keeps state in global variables. */
    InitMethods
};

PyMODINIT_FUNC
PyInit__init_openblas(void)
{
    PyObject *m;

    m = PyModule_Create(&initmodule);
    if (m == NULL)
        return NULL;

    return m;
}
