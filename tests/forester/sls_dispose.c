#include <stdlib.h>
#include <verifier-builtins.h>

typedef struct node {
  int data;
  struct node* next;
} node_t;

node_t* list_create() {
  node_t* x = NULL;
  node_t* y = NULL;

  while (__VERIFIER_nondet_int()) {
    y = malloc(sizeof(node_t));
    y->next = x;
    x = y;
  }
  return x;
}

node_t* singleton() {
  node_t* x = malloc(sizeof(node_t));
  x-> next = NULL;
  return x;
}


void list_destroy(node_t* lst) {
  node_t* x = lst;
  while (lst != NULL) {
    x = lst;
    lst = lst->next;
    free(x);
  }
}

void sls_dispose(node_t* lst)
{
  node_t* curr = lst;
  while (curr != NULL) 
  {
    node_t* tmp = curr;
    curr = curr->next; 
    free(tmp);
  }
}

int main() {
  sls_dispose(list_create());
  return 0;
}

